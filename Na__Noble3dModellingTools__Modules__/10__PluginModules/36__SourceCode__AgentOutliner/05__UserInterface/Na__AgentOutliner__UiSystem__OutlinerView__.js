// =============================================================================
// NA AGENT OUTLINER - UI SYSTEM - OUTLINER VIEW (THE TABLE)
// =============================================================================
//
// FILE       : Na__AgentOutliner__UiSystem__OutlinerView__.js
// NAMESPACE  : window.Na__AgentOutliner__View
// MODULE     : View (IIFE)
// AUTHOR     : Noble Architecture
// PURPOSE    : Draw the Outliner tab: the toolbar, the quick filters, the
//              agent bar, the Quick Name panel (a pop-out on the table's left
//              from 0.1.15), the table with its columns, and the footer; and
//              handle every click, key and right-click on them
// CREATED    : 10-Nov-2026
//
// DESCRIPTION:
// - ONLY THE ROWS ON SCREEN ARE DRAWN (plus a margin), on a canvas as tall as
//   all the rows: scrolling ten thousand rows costs the same as fifty.
//   SketchUp's own Outliner draws every row and stalls on big models.
// - COLUMNS: click a heading to sort (again to reverse, a third time to clear;
//   Shift adds a second key), drag its right edge to resize, drag the heading
//   to move it, right-click the headings to choose which show. All remembered.
// - TWO SELECTIONS: the outliner's own (rows picked here: flags, comments and
//   names act on it, across any groups; a red tint) and SketchUp's (a red bar
//   at the name; red from 0.1.15, as blue sat too close to the agent violet).
//   A click selects in SketchUp too, opening the parent group like SketchUp's
//   Outliner; a selection made in the model is found here and scrolled to the
//   middle of the table while the Follow switch is on (0.1.15, on by default).
// - STATUS COLOURS: rows are tinted by who changed them; the Colours switch
//   (grading.status_colours) turns the tint off and greys the status chips.
// - TREE BY TAG (0.1.16): each tag is a card in its tag colour (a heading, a
//   band down its left and a light wash behind its rows) with a gap above
//   it; tag folders are grey headings with a line down the cards they hold;
//   inside a card, guide lines join each object to its contents. Rows are
//   still 26 px; a heading's gap makes it taller, so rows are placed from a
//   table of tops (V.tops), not index x 26.
// - NOTHING IS WRITTEN AS A SIDE EFFECT OF SELECTING (SketchUp's Outliner has
//   renamed groups to "Group" when several were selected on Windows).
// - KEYS: arrows move (Shift extends), Right and Left open and close, Enter
//   zooms, F2 renames, Ctrl+A selects all rows, Ctrl+F searches, Ctrl+C copies
//   for an agent, Esc clears; Q opens and closes the Quick Name panel.
//
// =============================================================================

(function () {
    'use strict';

    var View  = {};
    var Shell = null;
    var Store = null;
    var Bridge = null;

    var NA_ROW_H    = 26;
    var NA_OVERSCAN = 12;
    var NA_COLUMNS = [
        { id: 'name',       label: 'Name',      width: 320, min: 140, sortable: true,  title: 'The name SketchUp shows. Components show their definition beside an instance name.' },
        { id: 'vis',        label: '',          width: 50,  min: 50,  sortable: false, title: 'Shown or hidden, locked or unlocked: click to switch.' },
        { id: 'status',     label: 'Status',    width: 112, min: 80,  sortable: true,  title: 'New or updated recently, and by whom. The colour fades as it ages (Settings).' },
        { id: 'changed',    label: 'Changed',   width: 92,  min: 70,  sortable: true,  title: 'When it was last made or changed.' },
        { id: 'flag',       label: 'Flag',      width: 112, min: 70,  sortable: true,  title: 'A flag for an agent (or one an agent left for you).' },
        { id: 'notes',      label: 'Notes',     width: 84,  min: 60,  sortable: true,  title: 'Comments: unread replies from an agent, and comments waiting for one.' },
        { id: 'type',       label: 'Type',      width: 96,  min: 60,  sortable: true,  title: 'Group, Component, Image or Section Plane.' },
        { id: 'definition', label: 'Definition', width: 170, min: 80, sortable: true,  title: 'A component\'s definition (shared by every copy).' },
        { id: 'instance',   label: 'Instance Name', width: 170, min: 80, sortable: true, title: 'This copy\'s own name (a group\'s name). Double-click to edit, or click it on a selected row.' },
        { id: 'tag',        label: 'Tag',       width: 150, min: 70,  sortable: true,  title: 'Its tag. Struck through when the tag (or its folder) is hidden.' },
        { id: 'size',       label: 'Size (mm)', width: 150, min: 90,  sortable: true,  title: 'Its own width x depth x height in mm (scale included).' },
        { id: 'copies',     label: 'Copies',    width: 66,  min: 50,  sortable: true,  title: 'How many copies share its definition: an edit inside reaches all of them.', hidden: true },
        { id: 'material',   label: 'Material',  width: 130, min: 70,  sortable: true,  title: 'The material painted on the group or component itself.', hidden: true },
        { id: 'prefix',     label: 'Prefix',    width: 160, min: 70,  sortable: true,  title: 'The standard name prefix it carries (Configure).', hidden: true },
        { id: 'by',         label: 'By',        width: 70,  min: 50,  sortable: true,  title: 'Who last made or changed it.', hidden: true },
        { id: 'pid',        label: 'ID',        width: 84,  min: 60,  sortable: true,  title: 'The persistent id agents use (entity_get, agent_outliner).' }
    ];
    var NA_VIEWS = [
        { value: 'tree',             label: 'Tree' },
        { value: 'tagtree',          label: 'Tree by Tag' },
        { value: 'cattree',          label: 'Group by Category' },
        { value: 'flat',             label: 'Flat List' },
        { value: 'group:tag',        label: 'Group by Tag' },
        { value: 'group:type',       label: 'Group by Type' },
        { value: 'group:definition', label: 'Group by Definition' },
        { value: 'group:flag',       label: 'Group by Flag' },
        { value: 'group:change',     label: 'Group by Change' },
        { value: 'group:by',         label: 'Group by Who Changed It' },
        { value: 'group:prefix',     label: 'Group by Prefix' },
        { value: 'group:parent',     label: 'Group by Parent' }
    ];

    var V = {
        columns: [], sel: {}, anchor: -1, focus: null, renaming: null, echoUntil: 0,
        follow: true, frame: 0, quickNameOpen: true, lastSelectionSent: '', followSig: '',
        tops: [0]
    };

    // FUNCTION | Where Each Row Starts (26 px rows; a Tree by Tag heading adds its gap above it, 0.1.16)
    // @return {number} the height of all the rows
    function na_layout_rows() {
        var rows = Store.na_state().rows;
        var tops = new Array(rows.length + 1);
        var y = 0;
        for (var i = 0; i < rows.length; i++) { tops[i] = y; y += NA_ROW_H + (rows[i].gap || 0); }
        tops[rows.length] = y;
        V.tops = tops;
        V.topsFor = rows;
        return y;
    }

    function na_top(index) {
        if (V.topsFor !== Store.na_state().rows) na_layout_rows();                       // <-- Rows rebuilt since: place them again
        return V.tops[Math.max(0, Math.min(index, V.tops.length - 1))];
    }

    // The row at a height down the table (the last one starting at or above it)
    function na_index_at(y) {
        if (V.topsFor !== Store.na_state().rows) na_layout_rows();
        var low = 0, high = V.tops.length - 2;
        if (high < 0) return 0;
        while (low < high) {
            var mid = (low + high + 1) >> 1;
            if (V.tops[mid] <= y) low = mid; else high = mid - 1;
        }
        return low;
    }

    // -------------------------------------------------------------------------
    // REGION | Columns
    // -------------------------------------------------------------------------

    function na_load_columns() {
        var saved = Shell.na_get_pref('columns', null);
        var byId = {};
        NA_COLUMNS.forEach(function (column) { byId[column.id] = column; });
        var list = [];
        if (Array.isArray(saved)) {
            saved.forEach(function (item) {
                var base = byId[item.id];
                if (!base || list.some(function (c) { return c.id === item.id; })) return;
                list.push({ id: base.id, w: Math.max(base.min, Number(item.w) || base.width), v: item.v !== false || base.id === 'name' });
            });
        }
        NA_COLUMNS.forEach(function (base, index) {
            if (list.some(function (c) { return c.id === base.id; })) return;
            var before = index > 0 ? list.findIndex(function (c) { return c.id === NA_COLUMNS[index - 1].id; }) : -1;   // <-- Beside its neighbour in a saved layout
            list.splice(before >= 0 ? before + 1 : list.length, 0, { id: base.id, w: base.width, v: !base.hidden });
        });
        var nameIndex = list.findIndex(function (c) { return c.id === 'name'; });
        if (nameIndex > 0) list.unshift(list.splice(nameIndex, 1)[0]);                       // <-- The tree column always comes first
        V.columns = list;
    }

    function na_save_columns() {
        Shell.na_set_pref('columns', V.columns.map(function (c) { return { id: c.id, w: c.w, v: c.v }; }));
    }

    function na_visible_columns() { return V.columns.filter(function (c) { return c.v; }); }
    function na_base(id) { return NA_COLUMNS.filter(function (c) { return c.id === id; })[0]; }

    function na_apply_grid() {
        var wrap = document.getElementById('na-ol-tablewrap');
        var columns = na_visible_columns();
        wrap.style.setProperty('--na-ol-grid', columns.map(function (c) { return c.w + 'px'; }).join(' '));
        var total = columns.reduce(function (sum, c) { return sum + c.w; }, 0);
        document.getElementById('na-ol-head').style.width = total + 'px';
        document.getElementById('na-ol-canvas').style.width = total + 'px';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Header
    // -------------------------------------------------------------------------

    function na_render_header() {
        var head = Shell.na_clear(document.getElementById('na-ol-head'));
        var sort = Store.na_state().sort;
        na_visible_columns().forEach(function (column) {
            var base = na_base(column.id);
            var cell = Shell.na_el('div', 'na-ol-hcell' + (base.sortable ? ' na-ol-hcell--sortable' : ''));
            cell.setAttribute('data-col', column.id);
            cell.title = base.title + (base.sortable ? ' Click to sort; Shift+click adds a second sort; drag to move.' : '');
            cell.appendChild(Shell.na_el('span', 'na-ol-hcell__label', base.label));
            sort.forEach(function (key, index) {
                if (key.col !== column.id) return;
                var mark = Shell.na_el('span', 'na-ol-hcell__sort', (key.dir > 0 ? '\u25b2' : '\u25bc') + (sort.length > 1 ? String(index + 1) : ''));
                cell.appendChild(mark);
            });
            if (column.id !== 'name') cell.draggable = true;
            var grip = Shell.na_el('span', 'na-ol-hcell__grip');
            grip.setAttribute('data-grip', column.id);
            cell.appendChild(grip);
            head.appendChild(cell);
        });
        na_apply_grid();
    }

    function na_wire_header() {
        var head = document.getElementById('na-ol-head');
        var dragging = null;

        head.addEventListener('click', function (event) {
            if (event.target.getAttribute('data-grip')) return;
            var cell = event.target.closest('.na-ol-hcell');
            if (!cell) return;
            var base = na_base(cell.getAttribute('data-col'));
            if (!base || !base.sortable) return;
            Store.na_toggle_sort(base.id, event.shiftKey);
            Shell.na_set_pref('sort', Store.na_state().sort);
            View.na_render();
        });

        head.addEventListener('contextmenu', function (event) {
            event.preventDefault();
            na_open_column_menu(event.clientX, event.clientY);
        });

        // Resize: drag a heading's right edge.
        head.addEventListener('mousedown', function (event) {
            var id = event.target.getAttribute('data-grip');
            if (!id) return;
            event.preventDefault();
            event.stopPropagation();
            var column = V.columns.filter(function (c) { return c.id === id; })[0];
            var startX = event.clientX, startW = column.w, min = na_base(id).min;
            var move = function (e) { column.w = Math.max(min, startW + e.clientX - startX); na_apply_grid(); };
            var up = function () {
                document.removeEventListener('mousemove', move);
                document.removeEventListener('mouseup', up);
                na_save_columns();
                na_render_window(true);
            };
            document.addEventListener('mousemove', move);
            document.addEventListener('mouseup', up);
        });

        // Move: drag a heading onto another.
        head.addEventListener('dragstart', function (event) {
            var cell = event.target.closest('.na-ol-hcell');
            if (!cell) return;
            dragging = cell.getAttribute('data-col');
            event.dataTransfer.effectAllowed = 'move';
            event.dataTransfer.setData('text/plain', dragging);
        });
        head.addEventListener('dragover', function (event) {
            if (!dragging) return;
            event.preventDefault();
            Array.prototype.forEach.call(head.querySelectorAll('.na-ol-hcell'), function (c) { c.classList.remove('na-ol-hcell--drop'); });
            var cell = event.target.closest('.na-ol-hcell');
            if (cell && cell.getAttribute('data-col') !== 'name') cell.classList.add('na-ol-hcell--drop');
        });
        head.addEventListener('drop', function (event) {
            event.preventDefault();
            var cell = event.target.closest('.na-ol-hcell');
            var target = cell ? cell.getAttribute('data-col') : null;
            if (dragging && target && target !== dragging && target !== 'name') {
                var from = V.columns.findIndex(function (c) { return c.id === dragging; });
                var moved = V.columns.splice(from, 1)[0];
                var to = V.columns.findIndex(function (c) { return c.id === target; });
                V.columns.splice(to, 0, moved);
                na_save_columns();
            }
            dragging = null;
            View.na_render();
        });
        head.addEventListener('dragend', function () { dragging = null; na_render_header(); });
    }

    function na_open_column_menu(x, y) {
        var items = V.columns.filter(function (c) { return c.id !== 'name'; }).map(function (column) {
            var base = na_base(column.id);
            return {
                label: (column.v ? '\u2713 ' : '\u2003 ') + (base.label || 'Shown / Locked'),
                action: function () { column.v = !column.v; na_save_columns(); View.na_render(); }
            };
        });
        items.push({ separator: true });
        items.push({ label: 'Reset Columns', action: function () { Shell.na_set_pref('columns', null); Shell.na_get_state().ui.columns = null; na_load_columns(); View.na_render(); } });
        View.na_menu(x, y, items);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Body (only the rows on screen)
    // -------------------------------------------------------------------------

    // FUNCTION | Rebuild the Rows and Draw Everything
    View.na_render = function () {
        if (!Store) return;
        Store.na_build_rows();
        na_render_header();
        var canvas = document.getElementById('na-ol-canvas');
        canvas.style.height = (na_layout_rows() + (Store.na_card_spec() ? 10 : 0)) + 'px';
        na_prune_selection();
        na_render_window(true);
        na_render_footer();
        na_render_chips();
        Shell.na_emit('uiSelection', View.na_selected_items());
    };

    function na_render_window(force) {
        var wrap   = document.getElementById('na-ol-tablewrap');
        var canvas = document.getElementById('na-ol-canvas');
        var rows   = Store.na_state().rows;
        var headH  = document.getElementById('na-ol-head').offsetHeight;
        var top    = Math.max(0, wrap.scrollTop - headH);
        var first  = Math.max(0, na_index_at(top) - NA_OVERSCAN);
        var last   = Math.min(rows.length, na_index_at(top + wrap.clientHeight) + 1 + NA_OVERSCAN);
        var frameKey = first + ':' + last + ':' + Store.na_state().version;
        if (!force && frameKey === V.frame) return;
        V.frame = frameKey;
        if (V.renaming) return;                                                            // <-- Never rebuild under the rename box
        Shell.na_clear(canvas);
        var fragment = document.createDocumentFragment();
        for (var i = first; i < last; i++) fragment.appendChild(na_row_element(rows[i], i));
        canvas.appendChild(fragment);
        if (!rows.length) canvas.appendChild(Shell.na_el('div', 'na-ol-empty', na_empty_text()));
    }

    function na_empty_text() {
        var S = Store.na_state();
        if (!S.model) return 'No model is open.';
        if (Store.na_filtering()) return 'Nothing matches. Clear the search or the filters (Esc).';
        return 'This model has no groups, components, images or section planes yet.';
    }

    function na_row_element(item, index) {
        var element = Shell.na_el('div', 'na-ol-row');
        element.style.top = na_top(index) + 'px';
        element.setAttribute('data-key', item.key);
        element.setAttribute('data-index', String(index));
        if (item.gap) {                                                                    // <-- The gap above a Tree by Tag heading is part of its row
            element.style.height = (NA_ROW_H + item.gap) + 'px';
            element.style.paddingTop = item.gap + 'px';
        }

        if (item.header && item.kind) return na_tt_heading(element, item);

        if (item.header) {
            element.classList.add('na-ol-row--header');
            var twisty = Shell.na_el('span', 'na-ol-twisty', item.open ? '\u25be' : '\u25b8');
            twisty.setAttribute('data-act', 'twisty');
            element.appendChild(twisty);
            if (item.colour) {
                var dot = Shell.na_el('span', 'na-ol-group-dot');
                dot.style.background = item.colour;
                element.appendChild(dot);
            }
            element.appendChild(Shell.na_el('span', 'na-ol-group-label', item.label));
            element.appendChild(Shell.na_el('span', 'na-ol-group-count', String(item.count)));
            return element;
        }

        var row = Store.na_row(item.pid);
        if (!row) return element;
        var S = Store.na_state();
        var change = Store.na_change(item.pid);
        if (V.sel[item.key]) element.classList.add('na-ol-row--selected');
        if (V.focus === item.key) element.classList.add('na-ol-row--focus');
        if (S.selectionIds[item.pid]) element.classList.add('na-ol-row--in-model');
        if (item.dim) element.classList.add('na-ol-row--context');
        if (row.h) element.classList.add('na-ol-row--hidden');
        if (!Store.na_tag_shown(row.t)) element.classList.add('na-ol-row--tag-hidden');
        if (na_ancestor_hidden(item)) element.classList.add('na-ol-row--parent-hidden');
        if (change && change.kind && View.na_status_colours()) {                          // <-- The Colours switch off: plain rows (0.1.15)
            var colour = change.by === 'agent' ? na_css_colour('--na-agent', '#7c3aed') : na_css_colour('--na-user', '#d97706');
            var alphas = [0.26, 0.17, 0.10, 0.05];
            element.style.setProperty('--na-row-tint', Shell.na_rgba(colour, alphas[Math.max(0, change.band)] || 0.05));
            element.style.setProperty('--na-row-edge', Shell.na_rgba(colour, [1, 0.8, 0.55, 0.3][Math.max(0, change.band)] || 0.3));
            element.classList.add('na-ol-row--changed');
        }

        na_visible_columns().forEach(function (column) {
            element.appendChild(na_cell(column.id, row, item, change));
        });
        if (item.tt) na_tt_decorate(element, item);
        return element;
    }

    // -------------------------------------------------------------------------
    // Tree by Tag: the cards (0.1.16)
    // Everything is placed on a 16 px grid: a heading at depth d has its band
    // at 6 + 16d and its arrow at 14 + 16d; its objects' arrows start one step
    // in. The decorations sit behind the row's text (z-index -1 in a row that
    // is its own stacking context).
    // -------------------------------------------------------------------------

    var NA_TT_FOLDER_LINE = 'rgba(100, 116, 139, 0.55)';

    function na_tt_x(depth) { return 6 + depth * 16; }

    function na_tt_piece(element, kind, left, top, extra) {
        var piece = Shell.na_el('span', 'na-ol-tt-' + kind + (extra ? ' ' + extra : ''));
        piece.style.left = left + 'px';
        piece.style.top = top + 'px';
        element.appendChild(piece);
        return piece;
    }

    // The bands of the folders (and the tag) a row sits in; a heading's own band starts below its gap.
    function na_tt_bands(element, item) {
        (item.bands || []).forEach(function (band, i, list) {
            var own = item.header && i === list.length - 1;
            if (band.kind === 'folder' && own) return;                                     // <-- A folder's line starts below its own heading
            var piece = na_tt_piece(element, 'band', na_tt_x(band.d) + (band.kind === 'folder' ? 1 : 0), own ? (item.gap || 0) : 0,
                                    'na-ol-tt-band--' + band.kind + (own ? ' na-ol-tt-band--start' : '') + (item.blockEnd && band.kind === 'tag' && i === list.length - 1 ? ' na-ol-tt-band--end' : ''));
            piece.style.background = band.kind === 'folder' ? NA_TT_FOLDER_LINE : band.colour;
        });
    }

    // A tag card's light wash behind a row, with the card's edge on the right and at its end.
    function na_tt_wash(element, item, alpha) {
        var tt = item.tt;
        var wash = na_tt_piece(element, 'wash', na_tt_x(tt.d), item.header ? (item.gap || 0) : 0,
                               (item.header ? 'na-ol-tt-wash--head' : '') + (item.blockEnd ? ' na-ol-tt-wash--end' : ''));
        wash.style.background = Shell.na_rgba(tt.colour, alpha);
        wash.style.setProperty('--na-tt-line', Shell.na_rgba(tt.colour, 0.42));
    }

    // An object row in a card: the wash, the bands, and a guide down from each open parent's arrow.
    function na_tt_decorate(element, item) {
        element.classList.add('na-ol-row--tt');
        na_tt_wash(element, item, 0.06);
        na_tt_bands(element, item);
        for (var j = 0; j < (item.level || 0); j++) {
            var guide = na_tt_piece(element, 'guide', 14 + 8 + (item.tt.d + 1 + j) * 16 - 1, 0);
            guide.style.background = Shell.na_rgba(item.tt.colour, 0.75);
        }
    }

    // A folder or tag heading: arrow, swatch or folder, name, and how many.
    function na_tt_heading(element, item) {
        element.classList.add('na-ol-row--header', 'na-ol-row--tt', 'na-ol-row--tthead', 'na-ol-row--tthead-' + item.kind);
        if (item.hidden) element.classList.add('na-ol-tt-hidden');
        if (V.focus === item.key) element.classList.add('na-ol-row--focus');
        element.style.paddingLeft = (14 + item.depth * 16) + 'px';
        if (item.kind === 'tag') na_tt_wash(element, item, 0.2);
        else {
            var bar = na_tt_piece(element, 'wash', na_tt_x(item.depth), item.gap || 0, 'na-ol-tt-wash--folder');
            bar.style.background = '#e7ebf0';
        }
        na_tt_bands(element, item);

        var twisty = Shell.na_el('span', 'na-ol-twisty', item.open ? '\u25be' : '\u25b8');
        twisty.setAttribute('data-act', 'twisty');
        element.appendChild(twisty);
        if (item.kind === 'tag') {
            var swatch = Shell.na_el('span', 'na-ol-tt-swatch');
            swatch.style.background = item.colour;
            element.appendChild(swatch);
        } else {
            element.appendChild(View.na_icon('folder'));
        }
        element.appendChild(Shell.na_el('span', 'na-ol-group-label', item.label));
        if (item.hidden) {
            var off = View.na_icon('eye-off');
            off.title = item.kind === 'tag' ? 'This tag is hidden in SketchUp' : 'This tag folder is hidden in SketchUp';
            element.appendChild(off);
        }
        element.appendChild(Shell.na_el('span', 'na-ol-group-count', item.kind === 'tag' ? String(item.count) : item.countText));

        element.title = na_tt_heading_title(item) + ' Click to open or close.';
        return element;
    }

    // What a card view's heading stands for (its tooltip)
    function na_tt_heading_title(item) {
        var objects = item.count + (item.count === 1 ? ' object' : ' objects');
        var placed = ', ' + item.roots + ' listed at the top of the card and the rest inside them.';
        if (item.view === 'cattree') {                                                     // <-- Group by Category (0.1.18)
            if (item.kind === 'folder') return item.label + ': a naming category (Configure) holding ' + item.countText + ' with objects.';
            if (!item.group) return 'No Standard Name: ' + objects + ' whose names carry no standard prefix. The top-level ones head this card; an unnamed part of a named object is listed inside that object, in its prefix\'s card.';
            var meaning = String((Store.na_prefix_entry(item.group) || {}).meaning || '').trim();
            if (meaning && !/[.!?]$/.test(meaning)) meaning += '.';                    // <-- Adam's short meanings have no full stop
            return item.label + ': ' + objects + ' named with this prefix' + placed + (meaning ? ' ' + meaning : '');
        }
        if (item.kind === 'folder') return item.label + ': a tag folder holding ' + item.countText + ' with objects' + (item.hidden ? ' (hidden in SketchUp)' : '') + '.';
        if (!item.group) return 'Untagged: ' + item.count + ' untagged objects. The top-level ones head this card; an untagged part of a tagged group is listed inside that group, in its tag\'s card.';
        return item.label + ': ' + objects + ' on this tag' + placed.slice(0, -1) + (item.hidden ? '. The tag is hidden in SketchUp.' : '.');
    }

    function na_cell(col, row, item, change) {
        var cell = Shell.na_el('div', 'na-ol-cell na-ol-cell--' + col);
        switch (col) {
            case 'name':       na_cell_name(cell, row, item); break;
            case 'vis':        na_cell_vis(cell, row); break;
            case 'status':     na_cell_status(cell, change); break;
            case 'changed':
                if (change && change.ever) {
                    cell.textContent = Shell.na_ago(change.latest);
                    cell.title = (change.kind === 'new' ? 'Made ' : 'Changed ') + Shell.na_when(change.latest) + ' by ' + (change.by === 'agent' ? 'an agent' : 'you') +
                        (change.fields.length ? ': ' + change.fields.join(', ') : '') + (change.tool ? ' (' + change.tool.replace('__', ' ') + ')' : '');
                }
                break;
            case 'flag':       na_cell_flag(cell, row); break;
            case 'notes':      na_cell_notes(cell, row); break;
            case 'type':       cell.textContent = Store.na_type_name(row.k) + (row.k === 's' && row.sa ? ' (active)' : ''); break;
            case 'definition': cell.textContent = Store.na_def_name(row); cell.title = cell.textContent; break;
            case 'instance':   na_cell_instance(cell, row, item); break;
            case 'tag':
                cell.setAttribute('data-act', 'tag');                                       // <-- Click a selected row's tag (or its caret) to change it
                if (!row.t) { cell.appendChild(Shell.na_el('span', 'na-ol-tag-name', 'Untagged')); cell.classList.add('na-ol-cell--muted'); }
                else {
                    var swatch = Shell.na_el('span', 'na-ol-tag-swatch');
                    swatch.style.background = Store.na_tag_colour(row.t) || 'transparent';
                    cell.appendChild(swatch);
                    cell.appendChild(Shell.na_el('span', 'na-ol-tag-name' + (Store.na_tag_shown(row.t) ? '' : ' na-ol-tag--off'), row.t));
                }
                cell.title = (row.t || 'Untagged') + (row.t && !Store.na_tag_shown(row.t) ? ' (hidden tag)' : '') + '. Click to change the tag (T).';
                var caret = Shell.na_el('span', 'na-ol-tag-caret', '\u25be');
                caret.setAttribute('data-act', 'tagcaret');
                cell.appendChild(caret);
                break;
            case 'size':       cell.textContent = Shell.na_size(row.sz); break;
            case 'copies':     if (row.d) cell.textContent = String(Store.na_copies(row)); break;
            case 'material':   cell.textContent = row.m || ''; cell.title = row.m || ''; break;
            case 'prefix':     cell.textContent = row.pre || ''; break;
            case 'by':
                if (change && change.ever) {
                    cell.appendChild(Shell.na_el('span', 'na-ol-by na-ol-by--' + change.by, change.by === 'agent' ? 'Agent' : 'Me'));
                }
                break;
            case 'pid':        cell.textContent = String(row.p); break;
        }
        return cell;
    }

    // The inline box shared by the Name and Instance Name cells
    function na_rename_box(cell) {
        var input = Shell.na_el('input', 'na-ol-rename');
        input.value = V.renaming.value;
        input.placeholder = 'No name of its own';
        cell.appendChild(input);
        window.setTimeout(function () { input.focus(); input.select(); }, 0);
        input.addEventListener('keydown', function (event) {
            event.stopPropagation();
            if (event.key === 'Enter') { event.preventDefault(); na_finish_rename(input.value, true); }
            if (event.key === 'Escape') { event.preventDefault(); na_finish_rename(null, false); }
        });
        input.addEventListener('click', function (event) { event.stopPropagation(); });
        input.addEventListener('dblclick', function (event) { event.stopPropagation(); });
        input.addEventListener('blur', function () { if (V.renaming) na_finish_rename(input.value, true); });
    }

    // Instance Name: the copy's own name (row.n), editable in place. Images cannot carry one.
    function na_cell_instance(cell, row, item) {
        if (V.renaming && V.renaming.key === item.key && V.renaming.col === 'instance') {
            na_rename_box(cell);
            return;
        }
        if (row.k === 'i' || row.k === 's') return;
        cell.setAttribute('data-act', 'instance');
        if (row.n) { cell.textContent = row.n; cell.title = row.n + ' (double-click to edit)'; }
        else { cell.textContent = 'No name'; cell.classList.add('na-ol-cell--muted'); cell.title = 'No name of its own: double-click to give it one'; }
    }

    function na_cell_name(cell, row, item) {
        cell.style.paddingLeft = (6 + (item.inset || 0) + item.depth * 16) + 'px';          // <-- Tree by Tag rows sit 8 px further in, clear of the card's band
        var twisty = Shell.na_el('span', 'na-ol-twisty' + (item.hasKids ? '' : ' na-ol-twisty--none'), item.hasKids ? (item.open ? '\u25be' : '\u25b8') : '');
        if (item.hasKids) twisty.setAttribute('data-act', 'twisty');
        cell.appendChild(twisty);
        cell.appendChild(View.na_icon(row.k));

        if (V.renaming && V.renaming.key === item.key && V.renaming.col === 'name') {
            na_rename_box(cell);
            return;
        }

        var label = Shell.na_el('span', 'na-ol-name');
        label.setAttribute('data-act', 'name');
        if (row.pre) {
            var entry = Store.na_prefix_entry(row.pre);
            var pip = Shell.na_el('span', 'na-ol-prefix-pip');
            pip.style.background = entry ? entry.colour : '#64748b';
            pip.title = row.pre + (entry ? ': ' + entry.meaning : '');
            cell.appendChild(pip);
        }
        if (row.k === 'c' && row.n) {
            label.appendChild(document.createTextNode(row.n + ' '));
            label.appendChild(Shell.na_el('span', 'na-ol-name__def', '<' + Store.na_def_name(row) + '>'));
        } else {
            label.textContent = row.dn;
            if (!row.n && (row.k === 'g' || row.k === 'c')) label.classList.add('na-ol-name--unnamed');
        }
        label.title = row.dn + (row.k === 'c' ? '  (' + Store.na_copies(row) + ' copies share ' + Store.na_def_name(row) + ')' : '');
        cell.appendChild(label);

        if (item.hasKids && !item.open) {
            var inside = Store.na_changes_inside(row);
            if (inside) {
                var dot = Shell.na_el('span', 'na-ol-inside-dot na-ol-inside-dot--' + inside.by);
                dot.title = 'Something inside was ' + (inside.by === 'agent' ? 'changed by an agent' : 'changed by you') + ' ' + Shell.na_ago(inside.latest);
                cell.appendChild(dot);
            }
        }
        if (row.cp) {
            var copied = Shell.na_el('span', 'na-ol-copied', 'copy');
            copied.title = 'Its notes came with it when it was copied from ' + row.cp + '.';
            cell.appendChild(copied);
        }
    }

    function na_cell_vis(cell, row) {
        var eye = Shell.na_el('span', 'na-ol-iconbtn' + (row.h ? ' na-ol-iconbtn--off' : ''));
        eye.setAttribute('data-act', 'eye');
        eye.title = row.h ? 'Hidden: click to show' : 'Shown: click to hide';
        eye.appendChild(View.na_icon(row.h ? 'eye-off' : 'eye'));
        cell.appendChild(eye);
        if (row.k === 'g' || row.k === 'c') {
            var lock = Shell.na_el('span', 'na-ol-iconbtn' + (row.l ? ' na-ol-iconbtn--on' : ' na-ol-iconbtn--faint'));
            lock.setAttribute('data-act', 'lock');
            lock.title = row.l ? 'Locked: click to unlock' : 'Unlocked: click to lock';
            lock.appendChild(View.na_icon(row.l ? 'lock' : 'unlock'));
            cell.appendChild(lock);
        }
    }

    function na_cell_status(cell, change) {
        if (!change || !change.kind) return;
        var chip = Shell.na_el('span', 'na-ol-chip na-ol-chip--' + change.by + ' na-ol-chip--band' + Math.max(0, change.band),
            (change.kind === 'new' ? 'NEW' : 'UPDATED') + (change.by === 'agent' ? ' \u00b7 AGENT' : ' \u00b7 ME'));
        chip.title = (change.kind === 'new' ? 'Made ' : 'Changed ') + Shell.na_ago(change.latest) + ' by ' + (change.by === 'agent' ? 'an agent' : 'you') +
            (change.fields.length ? ': ' + change.fields.join(', ') : '') + (change.unseen ? '. Not yet marked as seen.' : '');
        cell.appendChild(chip);
        if (change.unseen) cell.appendChild(Shell.na_el('span', 'na-ol-unseen', ''));
    }

    function na_cell_flag(cell, row) {
        cell.setAttribute('data-act', 'flag');
        if (!row.nf) { cell.appendChild(Shell.na_el('span', 'na-ol-flag-empty', '+')); return; }
        var type = Store.na_flag_type(row.nf);
        var chip = Shell.na_el('span', 'na-ol-flag', type ? type.label : row.nf);
        chip.style.setProperty('--na-flag', type ? type.colour : '#64748b');
        if (row.nfb === 'agent') chip.appendChild(Shell.na_el('span', 'na-ol-flag__by', 'A'));
        chip.title = (type ? type.meaning : 'This flag type is no longer in the standards.') + (row.nfb === 'agent' ? ' (set by an agent)' : '');
        cell.appendChild(chip);
    }

    function na_cell_notes(cell, row) {
        cell.setAttribute('data-act', 'notes');
        if (!row.nc && !row.nu && !row.nw) return;
        var bubble = Shell.na_el('span', 'na-ol-notes' + (row.ns === 'resolved' ? ' na-ol-notes--resolved' : ''));
        bubble.appendChild(View.na_icon('comment'));
        bubble.appendChild(document.createTextNode(String(row.nc || 0)));
        cell.appendChild(bubble);
        if (row.nu) cell.appendChild(Shell.na_el('span', 'na-ol-badge na-ol-badge--agent', row.nu + ' new'));
        if (row.nw) cell.appendChild(Shell.na_el('span', 'na-ol-badge na-ol-badge--user', 'waiting'));
        cell.title = (row.nlb === 'agent' ? 'Agent: ' : 'You: ') + (row.nl || '') + (row.ns === 'resolved' ? ' (resolved)' : '');
    }

    function na_ancestor_hidden(item) {
        if (!item.path || item.path.length < 2) return false;
        for (var i = 0; i < item.path.length - 1; i++) {
            var parent = Store.na_row(item.path[i]);
            if (parent && (parent.h || !Store.na_tag_shown(parent.t))) return true;
        }
        return false;
    }

    function na_css_colour(name, fallback) {
        var value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
        return value || fallback;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Icons (constant SVG, never built from model data)
    // -------------------------------------------------------------------------

    var NA_ICONS = {
        g:         '<svg viewBox="0 0 16 16"><rect x="2" y="2" width="12" height="12" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-dasharray="2.4 1.6"/></svg>',
        c:         '<svg viewBox="0 0 16 16"><path d="M8 1.8l5.6 3.1v6.2L8 14.2 2.4 11.1V4.9z" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M2.6 5L8 8l5.4-3M8 8v6" fill="none" stroke="currentColor" stroke-width="1.2"/></svg>',
        i:         '<svg viewBox="0 0 16 16"><rect x="2" y="3" width="12" height="10" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M3.5 11.5l3-3.5 2.2 2.4 1.6-1.6 2.2 2.7" fill="none" stroke="currentColor" stroke-width="1.2"/><circle cx="10.6" cy="6" r="1.1" fill="currentColor"/></svg>',
        s:         '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="5.6" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M2.4 8h11.2" stroke="currentColor" stroke-width="1.4"/><path d="M8 2.4v11.2" stroke="currentColor" stroke-width="0.9" stroke-dasharray="1.6 1.4"/></svg>',
        eye:       '<svg viewBox="0 0 16 16"><path d="M1.5 8s2.4-4.3 6.5-4.3S14.5 8 14.5 8s-2.4 4.3-6.5 4.3S1.5 8 1.5 8z" fill="none" stroke="currentColor" stroke-width="1.3"/><circle cx="8" cy="8" r="2" fill="currentColor"/></svg>',
        'eye-off': '<svg viewBox="0 0 16 16"><path d="M1.5 8s2.4-4.3 6.5-4.3S14.5 8 14.5 8s-2.4 4.3-6.5 4.3S1.5 8 1.5 8z" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M2.5 13.5l11-11" stroke="currentColor" stroke-width="1.5"/></svg>',
        lock:      '<svg viewBox="0 0 16 16"><rect x="3" y="7" width="10" height="7" rx="1.2" fill="currentColor"/><path d="M5.2 7V5.2a2.8 2.8 0 015.6 0V7" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>',
        unlock:    '<svg viewBox="0 0 16 16"><rect x="3" y="7" width="10" height="7" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.2"/><path d="M5.2 7V5.2a2.8 2.8 0 015.4-1" fill="none" stroke="currentColor" stroke-width="1.2"/></svg>',
        comment:   '<svg viewBox="0 0 16 16"><path d="M2.5 3.5h11v7h-6l-3 2.5v-2.5h-2z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>',
        folder:    '<svg viewBox="0 0 16 16"><path d="M1.8 4.2a1 1 0 011-1h3.4l1.5 1.6h5.5a1 1 0 011 1v6.4a1 1 0 01-1 1H2.8a1 1 0 01-1-1z" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>'
    };

    // HELPER FUNCTION | A Small Icon
    // @param name {string} g | c | i | s | eye | eye-off | lock | unlock | comment | folder
    // @return {HTMLElement}
    View.na_icon = function (name) {
        var span = Shell.na_el('span', 'na-ol-icon na-ol-icon--' + name);
        span.innerHTML = NA_ICONS[name] || '';
        return span;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Selecting Rows (the outliner's own selection)
    // -------------------------------------------------------------------------

    // FUNCTION | The Selected Rows (items with path and pid)
    View.na_selected_items = function () {
        var rows = Store.na_state().rows;
        return rows.filter(function (item) { return !item.header && V.sel[item.key]; });
    };

    // FUNCTION | The Selected Objects' Persistent Ids (each once)
    View.na_selected_pids = function () {
        var seen = {};
        var list = [];
        View.na_selected_items().forEach(function (item) { if (!seen[item.pid]) { seen[item.pid] = true; list.push(item.pid); } });
        return list;
    };

    function na_prune_selection() {
        var keys = {};
        Store.na_state().rows.forEach(function (item) { keys[item.key] = true; });
        Object.keys(V.sel).forEach(function (key) { if (!keys[key]) delete V.sel[key]; });
    }

    function na_select_index(index, mode) {
        var rows = Store.na_state().rows;
        var item = rows[index];
        if (!item) return;
        if (mode === 'toggle') {
            if (V.sel[item.key]) delete V.sel[item.key]; else V.sel[item.key] = true;
            V.anchor = index;
        } else if (mode === 'range' && V.anchor >= 0) {
            V.sel = {};
            var from = Math.min(V.anchor, index), to = Math.max(V.anchor, index);
            for (var i = from; i <= to; i++) if (!rows[i].header) V.sel[rows[i].key] = true;
        } else {
            V.sel = {};
            if (!item.header) V.sel[item.key] = true;
            V.anchor = index;
        }
        V.focus = item.key;
        na_render_window(true);
        Shell.na_emit('uiSelection', View.na_selected_items());
        na_send_selection(false);
    }

    // Selects the rows' objects in SketchUp (one call per burst of clicks).
    var na_select_timer = null;
    function na_send_selection(zoom, force) {
        var items = View.na_selected_items();
        if (!items.length) return;
        var paths = items.map(function (item) { return item.path; }).filter(Boolean);
        var signature = JSON.stringify(paths) + (zoom ? '|z' : '');
        if (na_select_timer) window.clearTimeout(na_select_timer);
        na_select_timer = window.setTimeout(function () {
            na_select_timer = null;
            if (signature === V.lastSelectionSent && !zoom && !force) return;
            V.lastSelectionSent = signature;
            V.echoUntil = Date.now() + 900;
            Bridge.na_call('select', { paths: paths.slice(0, 2000), zoom: !!zoom });
        }, 60);
    }

    // FUNCTION | SketchUp's Selection Arrived (highlight; follow it when asked)
    // 0.1.15 (Adam: "move [to] the item in the table that's selected inside
    // sketchup viewport and add a toggle on by default"): with Follow on, a
    // selection made in the model opens the tree (or its group heading) to the
    // object, selects its row and scrolls it to the middle of the table. Only
    // a selection that CHANGED is followed: Ruby sends the selection again
    // after every operation, and following that would pull the table back
    // each time Adam scrolled away while modelling. Loose geometry picked
    // inside an open group follows the group. force (Reveal Selection, the
    // switch turned on) follows whatever is selected now.
    // @param selection {{ids: number[], active: number[]}}
    // @param force     {boolean}
    View.na_model_selection = function (selection, force) {
        Store.na_set_selection(selection || {});
        var S = Store.na_state();
        var echo = Date.now() < V.echoUntil;
        var paths = Store.na_selection_paths();
        var signature = JSON.stringify(paths) + '|' + (S.activePath || []).join('/');
        var changed = signature !== V.followSig;
        V.followSig = signature;                                                       // <-- Our own click's echo counts as seen too
        if (force || (changed && !echo && View.na_following())) {
            if (paths.length) return na_follow_paths(paths);
            if (S.activePath && S.activePath.length) return na_follow_open_group(S.activePath);
        }
        na_render_window(true);
        na_render_footer();
    };

    function na_follow_paths(paths) {
        var S = Store.na_state();
        var homes = {};
        if (S.view === 'tree') paths.slice(0, 50).forEach(function (path) { Store.na_reveal(path); });
        else if (Store.na_card_spec()) Store.na_reveal_cards(paths).forEach(function (key) { homes[key] = true; });   // <-- Its own card (0.1.16)
        else Store.na_reveal_groups(paths.map(function (path) { return path[path.length - 1]; }));
        Store.na_build_rows();
        var wanted = {};
        paths.forEach(function (path) { wanted[path.join('/')] = true; wanted['pid:' + path[path.length - 1]] = true; });
        V.sel = {};
        var firstIndex = -1, homeIndex = -1;
        Store.na_state().rows.forEach(function (item, index) {
            if (item.header) return;
            var hit = Store.na_state().view === 'tree' ? wanted[item.key] : wanted['pid:' + item.pid];
            if (hit) { V.sel[item.key] = true; if (firstIndex < 0) firstIndex = index; }
            if (hit && homes[item.key] && homeIndex < 0) homeIndex = index;               // <-- Listed in two cards: scroll to its own
        });
        if (homeIndex >= 0) firstIndex = homeIndex;
        if (firstIndex >= 0) { V.focus = Store.na_state().rows[firstIndex].key; V.anchor = firstIndex; }
        V.lastSelectionSent = JSON.stringify(paths);
        View.na_render();
        if (firstIndex >= 0) na_scroll_to(firstIndex, true);
        else if (Store.na_filtering()) Shell.na_set_status('What is selected in SketchUp is not listed: the search or a filter hides it (Esc clears them).', 'info');
    }

    // Faces and edges picked inside an open group: show the group being edited.
    function na_follow_open_group(path) {
        var S = Store.na_state();
        var pid = path[path.length - 1];
        var homeKey = '';
        if (S.view === 'tree') Store.na_reveal(path);
        else if (Store.na_card_spec()) homeKey = Store.na_reveal_cards([path])[0] || '';
        else Store.na_reveal_groups([pid]);
        View.na_render();
        var key = homeKey || path.join('/');
        var index = Store.na_state().rows.findIndex(function (item) {
            return !item.header && (item.key === key || (Store.na_state().view !== 'tree' && item.pid === pid));
        });
        if (index >= 0) na_scroll_to(index, true);
    }

    // FUNCTION | Bring a Row on Screen
    // centre true (following SketchUp): a row not comfortably on screen (two
    // rows clear of either edge) goes to the middle. Otherwise (the arrow
    // keys): only a row off screen moves, to the top edge or the middle.
    function na_scroll_to(index, centre) {
        var wrap = document.getElementById('na-ol-tablewrap');
        var headH = document.getElementById('na-ol-head').offsetHeight;
        var view = wrap.clientHeight - headH;
        var top = na_top(index) + (Store.na_state().rows[index] && Store.na_state().rows[index].gap || 0);
        var margin = centre ? Math.min(NA_ROW_H * 2, Math.max(0, (view - NA_ROW_H) / 2)) : 0;
        var viewTop = wrap.scrollTop + margin, viewBottom = wrap.scrollTop + view - NA_ROW_H - margin;
        if (top >= viewTop && top <= viewBottom) return;
        if (centre) wrap.scrollTop = Math.max(0, top - (view - NA_ROW_H) / 2);
        else if (top < viewTop) wrap.scrollTop = top;
        else wrap.scrollTop = top - view / 2;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Follow and Colours Switches (0.1.15)
    // -------------------------------------------------------------------------
    // Both are settings (selection.follow_selection, grading.status_colours),
    // shown on the Settings tab too. A click applies at once and saves only
    // that one setting; Ruby keeps just Adam's differences from the defaults.

    function na_setting(group, key, fallback) {
        var settings = Store.na_state().settings || {};
        var values = settings[group] || {};
        return values[key] === undefined || values[key] === null ? fallback : values[key];
    }

    // FUNCTION | Is Follow Selection On? (on unless switched off)
    View.na_following = function () { return na_setting('selection', 'follow_selection', true) !== false; };

    // FUNCTION | Are the Status Colours On? (on unless switched off)
    View.na_status_colours = function () { return na_setting('grading', 'status_colours', true) !== false; };

    function na_save_switch(group, key, value, message) {
        var S = Store.na_state();
        S.settings = S.settings || {};
        S.settings[group] = S.settings[group] || {};
        S.settings[group][key] = value;                                                // <-- At once; the state Ruby sends back agrees
        var patch = {};
        patch[group] = {};
        patch[group][key] = value;
        Bridge.na_call('saveSettings', { settings: patch, message: message });
    }

    function na_render_switches() {
        var follow = View.na_following();
        var colours = View.na_status_colours();
        var followBtn = document.getElementById('na-ol-follow');
        followBtn.setAttribute('aria-pressed', follow ? 'true' : 'false');
        followBtn.title = follow
            ? 'Follow Selection is on: whatever you select in SketchUp is found in the table and scrolled into view. Click to turn it off.'
            : 'Follow Selection is off: the table stays where it is when you select in SketchUp (Reveal Selection finds it once). Click to turn it on.';
        var coloursBtn = document.getElementById('na-ol-colours');
        coloursBtn.setAttribute('aria-pressed', colours ? 'true' : 'false');
        coloursBtn.title = colours
            ? 'Status Colours are on: rows are tinted by who changed them (agent violet, you amber). Click to turn them off.'
            : 'Status Colours are off: rows are plain and the status chips grey. Click to colour them again.';
        document.getElementById('na-ol-tablewrap').classList.toggle('na-ol--plain', !colours);
        var legend = document.getElementById('na-ol-legend');
        if (legend) legend.classList.toggle('na-hidden', !colours);
    }

    function na_wire_switches() {
        document.getElementById('na-ol-follow').addEventListener('click', function () {
            var on = !View.na_following();
            na_save_switch('selection', 'follow_selection', on,
                on ? 'Follow Selection on: the table finds what you select in SketchUp.' : 'Follow Selection off: the table stays where you leave it.');
            na_render_switches();
            if (on) View.na_model_selection({ ids: Object.keys(Store.na_state().selectionIds).map(Number), active: Store.na_state().activePath }, true);
        });
        document.getElementById('na-ol-colours').addEventListener('click', function () {
            var on = !View.na_status_colours();
            na_save_switch('grading', 'status_colours', on,
                on ? 'Status Colours on: rows are tinted by who changed them.' : 'Status Colours off: plain rows.');
            na_render_switches();
            na_render_window(true);
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Clicks, Double Clicks, Right Clicks
    // -------------------------------------------------------------------------

    function na_wire_body() {
        var wrap   = document.getElementById('na-ol-tablewrap');
        var canvas = document.getElementById('na-ol-canvas');

        wrap.addEventListener('scroll', function () {
            window.requestAnimationFrame(function () { na_render_window(false); });
        });

        canvas.addEventListener('click', function (event) {
            var rowEl = event.target.closest('.na-ol-row');
            if (!rowEl) return;
            var index = Number(rowEl.getAttribute('data-index'));
            var item  = Store.na_state().rows[index];
            if (!item) return;
            var act = event.target.closest('[data-act]');
            act = act ? act.getAttribute('data-act') : '';
            wrap.focus({ preventScroll: true });

            // A double-click, told by row and time: the first click redraws the row, so the
            // browser's own dblclick never reaches a row that was not already selected.
            var now = Date.now();
            var last = V.lastClick;
            V.lastClick = { key: item.key, t: now, x: event.clientX, y: event.clientY };
            var plain = !event.shiftKey && !event.ctrlKey && !event.metaKey && !event.altKey;
            if (plain && !item.header && last && last.key === item.key && now - last.t < 500 &&
                Math.abs(last.x - event.clientX) < 8 && Math.abs(last.y - event.clientY) < 8 &&
                act !== 'twisty' && act !== 'eye' && act !== 'lock' && act !== 'flag') {
                V.lastClick = null;
                window.clearTimeout(V.instanceClick);
                na_on_double(item, event.target);
                return;
            }

            if ((act === 'tag' || act === 'tagcaret') && !item.header) {
                var tagIsSelected = !!V.sel[item.key];
                if (!tagIsSelected) na_select_index(index, plain ? 'single' : (event.shiftKey ? 'range' : 'toggle'));
                if (act === 'tagcaret' || (tagIsSelected && plain)) {
                    var cellEl = (document.querySelector('.na-ol-row[data-key="' + CSS.escape(item.key) + '"] .na-ol-cell--tag') || rowEl).getBoundingClientRect();
                    window.clearTimeout(V.tagClick);                                        // <-- Wait out a double-click on the same cell
                    V.tagClick = window.setTimeout(function () { View.na_tag_picker(cellEl.left, cellEl.bottom + 2, View.na_selected_pids()); }, act === 'tagcaret' ? 0 : 220);
                }
                return;
            }

            if (act === 'instance' && V.sel[item.key] && View.na_selected_pids().length === 1 && !event.shiftKey && !event.ctrlKey && !event.metaKey) {
                window.clearTimeout(V.instanceClick);                                       // <-- Wait out a double-click, which edits too
                V.instanceClick = window.setTimeout(function () { View.na_start_rename(item, 'instance'); }, 260);
                return;
            }

            if (act === 'twisty' || item.header) {
                Store.na_toggle_open(item);
                if (event.altKey && !item.header && !item.open) Store.na_expand_below(item, 3000);
                View.na_render();
                return;
            }
            if (act === 'eye' || act === 'lock') {
                var targets = V.sel[item.key] ? View.na_selected_pids() : [item.pid];
                var row = Store.na_row(item.pid);
                if (act === 'eye') Bridge.na_call('setHidden', { pids: targets, hidden: !row.h });
                else Bridge.na_call('setLocked', { pids: targets, locked: !row.l });
                return;
            }
            if (act === 'flag') {
                if (!V.sel[item.key]) na_select_index(index, 'single');
                var rect = event.target.getBoundingClientRect();
                View.na_flag_menu(rect.left, rect.bottom + 2);
                return;
            }
            na_select_index(index, event.shiftKey ? 'range' : ((event.ctrlKey || event.metaKey) ? 'toggle' : 'single'));
            if (act === 'notes') Shell.na_emit('focusThread', item.pid);
        });

        // The browser's dblclick is not used: the click handler tells a double-click itself
        // (na_on_double), because a click that selects redraws the row under the pointer.
        canvas.addEventListener('dblclick', function (event) { event.preventDefault(); });

        canvas.addEventListener('contextmenu', function (event) {
            event.preventDefault();
            var rowEl = event.target.closest('.na-ol-row');
            if (!rowEl) return;
            var index = Number(rowEl.getAttribute('data-index'));
            var item = Store.na_state().rows[index];
            if (!item || item.header) return;
            if (!V.sel[item.key]) na_select_index(index, 'single');
            na_open_row_menu(event.clientX, event.clientY, item);
        });

        wrap.addEventListener('keydown', na_on_key);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Keyboard
    // -------------------------------------------------------------------------

    // FUNCTION | ] and [ Open and Close the Tree a Level at a Time; Shift Does Them All (0.1.12)
    // Adam: "Make the [ and ] keys open levels or collapse levels of the tree".
    // Anywhere on the Outliner tab except a text field, so they work straight
    // after a click on a button as well as in the table.
    function na_on_level_key(event) {
        if (event.ctrlKey || event.metaKey || event.altKey || event.defaultPrevented) return;
        var key = event.key;
        if (key !== '[' && key !== ']' && key !== '{' && key !== '}') return;
        var panel = document.getElementById('na-tab-outliner');
        if (!panel || panel.classList.contains('na-hidden')) return;
        var target = event.target;
        if (target && (/INPUT|TEXTAREA|SELECT/.test(target.tagName) || target.isContentEditable)) return;
        event.preventDefault();
        View.na_close_menu();
        var open = key === ']' || key === '}';
        if (key === '{' || key === '}' || event.shiftKey) {                   // Shift+[ and Shift+] ({ and }, or [ ] with Shift held): the Collapse and Expand buttons
            if (open) {
                var result = Store.na_expand_below(null, 5000);
                View.na_render();
                Shell.na_set_status(result.capped ? 'Opened the first 5,000 rows (Shift+]). [ closes a level.' : 'Opened every level (Shift+]). [ closes one.', 'info');
            } else {
                Store.na_collapse_all();
                View.na_render();
                Shell.na_set_status('Closed every level (Shift+[). ] opens one.', 'info');
            }
            return;
        }
        var step = Store.na_step_level(Store.na_state().rows, open);
        if (!step) { Shell.na_set_status(open ? 'Every level is open. [ closes one.' : 'Every level is closed. ] opens one.', 'info'); return; }
        View.na_render();
        var what = step.groups ? step.count + ' group' + (step.count === 1 ? '' : 's')
                               : step.count + ' row' + (step.count === 1 ? '' : 's') + ' at level ' + (step.level + 1);
        Shell.na_set_status((open ? 'Opened ' : 'Closed ') + what + '. ' + (open ? '] opens the next level, [ closes it.' : '[ closes the next level, ] opens it.'), 'info');
    }

    function na_on_key(event) {
        if (event.target && /INPUT|TEXTAREA|SELECT/.test(event.target.tagName)) return;
        var rows = Store.na_state().rows;
        var index = rows.findIndex(function (item) { return item.key === V.focus; });
        var ctrl = event.ctrlKey || event.metaKey;
        var handled = true;
        switch (event.key) {
            case 'ArrowDown':  na_select_index(Math.min(rows.length - 1, index + 1), event.shiftKey ? 'range' : 'single'); na_scroll_to(Math.min(rows.length - 1, index + 1)); break;
            case 'ArrowUp':    na_select_index(Math.max(0, index - 1), event.shiftKey ? 'range' : 'single'); na_scroll_to(Math.max(0, index - 1)); break;
            case 'Home':       na_select_index(0, 'single'); na_scroll_to(0); break;
            case 'End':        na_select_index(rows.length - 1, 'single'); na_scroll_to(rows.length - 1); break;
            case 'ArrowRight':
                if (index >= 0 && (rows[index].hasKids || rows[index].header) && !rows[index].open) { Store.na_toggle_open(rows[index], true); View.na_render(); }
                else if (index >= 0 && rows[index].open) { na_select_index(index + 1, 'single'); }
                break;
            case 'ArrowLeft':
                if (index >= 0 && (rows[index].open || (rows[index].header && !rows[index].parentKey))) { Store.na_toggle_open(rows[index], false); View.na_render(); }
                else if (index >= 0 && (rows[index].parentKey || (rows[index].path && rows[index].path.length > 1))) {
                    var parentKey = rows[index].parentKey || rows[index].path.slice(0, -1).join('/');   // <-- Tree by Tag: the card's heading, or the folder (0.1.16)
                    var parentIndex = rows.findIndex(function (item) { return item.key === parentKey; });
                    if (parentIndex >= 0) { na_select_index(parentIndex, 'single'); na_scroll_to(parentIndex); }
                }
                break;
            case 'Enter':      na_send_selection(true); break;
            case 'F2':         if (index >= 0 && !rows[index].header) View.na_start_rename(rows[index]); break;
            case 'Escape':
                if (Store.na_filtering()) { View.na_clear_filters(); }
                else { V.sel = {}; na_render_window(true); Shell.na_emit('uiSelection', []); }
                break;
            case 't': case 'T':
                if (ctrl || event.altKey) { handled = false; break; }
                var focusEl = document.querySelector('.na-ol-row[data-key="' + CSS.escape(V.focus || '') + '"] .na-ol-cell--tag') ||
                              document.querySelector('.na-ol-row--selected') || document.getElementById('na-ol-tablewrap');
                var focusRect = focusEl.getBoundingClientRect();
                View.na_tag_picker(focusRect.left, Math.min(focusRect.bottom + 2, window.innerHeight - 40), View.na_selected_pids());
                break;
            case 'a': case 'A':
                if (!ctrl) { handled = false; break; }
                V.sel = {};
                rows.forEach(function (item) { if (!item.header) V.sel[item.key] = true; });
                na_render_window(true);
                Shell.na_emit('uiSelection', View.na_selected_items());
                break;
            case 'c': case 'C':
                if (!ctrl) { handled = false; break; }
                window.Na__AgentOutliner__Handoff.na_copy(View.na_selected_pids());
                break;
            case 'f': case 'F':
                if (!ctrl) { handled = false; break; }
                document.getElementById('na-ol-search').focus();
                break;
            default: handled = false;
        }
        if (handled) event.preventDefault();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Renaming
    // -------------------------------------------------------------------------

    // FUNCTION | A Double-Click on a Row: rename in Name or Instance Name, the tag picker on Tag, else zoom
    function na_on_double(item, target) {
        window.clearTimeout(V.tagClick);
        var cell = target && target.closest ? target.closest('.na-ol-cell') : null;
        if (cell && cell.classList.contains('na-ol-cell--name'))     { View.na_start_rename(item, 'name'); return; }
        if (cell && cell.classList.contains('na-ol-cell--instance')) { View.na_start_rename(item, 'instance'); return; }
        if (cell && cell.classList.contains('na-ol-cell--tag')) {
            var rect = cell.getBoundingClientRect();
            View.na_tag_picker(rect.left, rect.bottom + 2, V.sel[item.key] ? View.na_selected_pids() : [item.pid]);
            return;
        }
        var settings = Store.na_state().settings.selection || {};
        if (settings.zoom_on_double !== false) na_send_selection(true);
    }

    // FUNCTION | Rename in Place (several selected: a prompt names them all)
    View.na_start_rename = function (item, col) {
        col = col === 'instance' ? 'instance' : 'name';
        var pids = V.sel[item.key] ? View.na_selected_pids() : [item.pid];
        if (pids.length > 1) {
            Shell.na_prompt({
                title: 'Rename ' + pids.length + ' Objects', label: 'Name', value: '', confirm: 'Rename',
                hint: 'Each gets the name with __01, __02 ... in the order they are listed. Components keep their definition name.'
            }, function (text) { Bridge.na_call('rename', { pids: pids, name: text }); });
            return;
        }
        var row = Store.na_row(item.pid);
        if (!row || row.k === 'i') { Shell.na_set_status('Images cannot carry a name in SketchUp.', 'warn'); return; }
        V.renaming = null;
        na_render_window(true);                                                            // <-- The row is drawn first, then its name cell becomes the box
        if (col === 'instance' && row.k === 's') { Shell.na_set_status('Section planes are renamed in the Name column.', 'warn'); return; }
        var cellClass = '.na-ol-cell--' + col;
        if (col === 'instance' && !document.querySelector('.na-ol-row[data-key="' + CSS.escape(item.key) + '"] ' + cellClass)) col = 'name';   // <-- Column hidden: edit in Name
        V.renaming = { key: item.key, pid: item.pid, value: row.n || '', col: col };
        var cell = document.querySelector('.na-ol-row[data-key="' + CSS.escape(item.key) + '"] .na-ol-cell--' + col);
        if (cell) {
            Shell.na_clear(cell);
            if (col === 'instance') na_cell_instance(cell, row, item); else na_cell_name(cell, row, item);
        } else {
            V.renaming = null;
        }
    };

    function na_finish_rename(value, commit) {
        var renaming = V.renaming;
        V.renaming = null;
        if (commit && renaming && value !== null) {
            var row = Store.na_row(renaming.pid);
            if (row && value.trim() !== (row.n || '')) Bridge.na_call('rename', { pids: [renaming.pid], name: value.trim() });
        }
        na_render_window(true);
        document.getElementById('na-ol-tablewrap').focus({ preventScroll: true });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Menus (rows, flags, columns) and Actions on the Selection
    // -------------------------------------------------------------------------

    // FUNCTION | A Small Menu at a Point (items: {label, action, sub, separator, disabled})
    View.na_menu = function (x, y, items) {
        var menu = Shell.na_clear(document.getElementById('na-menu'));
        menu.classList.remove('na-menu--tags');
        var build = function (host, list) {
            list.forEach(function (entry) {
                if (entry.separator) { host.appendChild(Shell.na_el('div', 'na-menu__sep')); return; }
                if (entry.heading) { host.appendChild(Shell.na_el('div', 'na-menu__heading', entry.heading)); return; }
                var line = Shell.na_el('div', 'na-menu__item' + (entry.disabled ? ' na-menu__item--disabled' : '') + (entry.sub ? ' na-menu__item--sub' : ''));
                if (entry.colour) {
                    var dot = Shell.na_el('span', 'na-menu__dot');
                    dot.style.background = entry.colour;
                    line.appendChild(dot);
                }
                line.appendChild(Shell.na_el('span', 'na-menu__label', entry.label));
                if (entry.keys) line.appendChild(Shell.na_el('span', 'na-menu__keys', entry.keys));
                if (entry.sub) {
                    var flyout = Shell.na_el('div', 'na-menu na-menu--flyout');
                    build(flyout, entry.sub);
                    line.appendChild(flyout);
                } else if (!entry.disabled) {
                    line.addEventListener('click', function (event) {
                        event.stopPropagation();
                        View.na_close_menu();
                        entry.action();
                    });
                }
                if (entry.title) line.title = entry.title;
                host.appendChild(line);
            });
        };
        build(menu, items);
        menu.classList.remove('na-hidden');
        var width = menu.offsetWidth, height = menu.offsetHeight;
        menu.style.left = Math.max(4, Math.min(x, window.innerWidth - width - 6)) + 'px';
        menu.style.top  = Math.max(4, Math.min(y, window.innerHeight - height - 6)) + 'px';
        menu.classList.toggle('na-menu--flip', x + width * 2 > window.innerWidth);
    };

    View.na_close_menu = function () { document.getElementById('na-menu').classList.add('na-hidden'); };

    // FUNCTION | The Tag Picker: type to find a tag (or make one), Enter or click puts every object on it
    // One "Agent Outliner: Tag" undo step. The last tags used come first. (Adam, 11-Nov-2026)
    View.na_tag_picker = function (x, y, pids) {
        pids = (pids || []).filter(function (pid) { var row = Store.na_row(pid); return !!row; });
        if (!pids.length) return Shell.na_set_status('Select rows first, then change their tag (T).', 'warn');
        var S = Store.na_state();
        var counts = {};
        Object.keys(S.ents || {}).forEach(function (pid) { var t = S.ents[pid].t || ''; counts[t] = (counts[t] || 0) + 1; });
        var current = null;
        pids.forEach(function (pid) { var t = Store.na_row(pid).t || ''; current = current === null ? t : (current === t ? t : false); });
        var names = Object.keys(S.tags || {}).sort(function (a, b) { return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }); });
        var recent = (Shell.na_get_pref('recentTags', []) || []).filter(function (name) { return name === '' || S.tags[name]; }).slice(0, 5);

        var menu = Shell.na_clear(document.getElementById('na-menu'));
        menu.classList.add('na-menu--tags');
        menu.appendChild(Shell.na_el('div', 'na-tagpick__head', pids.length === 1 ? 'Tag for ' + (Store.na_row(pids[0]).dn || 'this object') : 'Tag for ' + pids.length + ' objects'));
        var input = Shell.na_el('input', 'na-tagpick__search');
        input.type = 'text';
        input.placeholder = 'Type to find a tag, or a new name';
        input.setAttribute('spellcheck', 'false');
        menu.appendChild(input);
        var list = Shell.na_el('div', 'na-tagpick__list');
        menu.appendChild(list);
        menu.appendChild(Shell.na_el('div', 'na-tagpick__foot', '\u2191\u2193 choose \u00b7 Enter apply \u00b7 Esc close'));
        var choices = [];
        var active = 0;

        function apply(choice) {
            View.na_close_menu();
            var keep = [choice.name].concat((Shell.na_get_pref('recentTags', []) || []).filter(function (name) { return name !== choice.name; })).slice(0, 8);
            Shell.na_set_pref('recentTags', keep);
            Bridge.na_call('setTag', { pids: pids, tag: choice.name, create: !!choice.create });
            document.getElementById('na-ol-tablewrap').focus({ preventScroll: true });
        }

        function line(choice, index) {
            var el = Shell.na_el('div', 'na-tagpick__item' + (index === active ? ' na-tagpick__item--active' : '') + (choice.create ? ' na-tagpick__item--create' : ''));
            var swatch = Shell.na_el('span', 'na-ol-tag-swatch');
            swatch.style.background = choice.create || !choice.name ? 'transparent' : (Store.na_tag_colour(choice.name) || 'transparent');
            if (choice.create) swatch.classList.add('na-tagpick__plus');
            el.appendChild(swatch);
            var label = Shell.na_el('span', 'na-tagpick__label' + (choice.name && !choice.create && !Store.na_tag_shown(choice.name) ? ' na-ol-tag--off' : ''),
                                    choice.create ? 'Make tag \u201c' + choice.name + '\u201d' : (choice.name || 'Untagged'));
            el.appendChild(label);
            if (!choice.create && current === choice.name) el.appendChild(Shell.na_el('span', 'na-tagpick__tick', '\u2713'));
            if (!choice.create) el.appendChild(Shell.na_el('span', 'na-tagpick__count', String(counts[choice.name] || 0)));
            el.title = choice.create ? 'Make a new tag with this name and put the ' + (pids.length === 1 ? 'object' : pids.length + ' objects') + ' on it'
                                     : (choice.name || 'Untagged') + ': ' + (counts[choice.name] || 0) + ' object(s) on it now';
            el.addEventListener('mousedown', function (event) { event.preventDefault(); });   // <-- Keep the typing box focused
            el.addEventListener('click', function (event) { event.stopPropagation(); apply(choice); });
            el.addEventListener('mousemove', function () { if (active !== index) { active = index; draw(false); } });
            return el;
        }

        function draw(rebuild) {
            if (rebuild !== false) {
                var text = input.value.trim();
                var low = text.toLowerCase();
                choices = [];
                if (!text) {
                    if (recent.length) {
                        choices.push({ heading: 'Recent' });
                        recent.forEach(function (name) { choices.push({ name: name }); });
                        choices.push({ heading: 'All Tags' });
                    }
                    choices.push({ name: '' });
                    names.forEach(function (name) { choices.push({ name: name }); });
                } else {
                    var starts = names.filter(function (name) { return name.toLowerCase().indexOf(low) === 0; });
                    var inside = names.filter(function (name) { return name.toLowerCase().indexOf(low) > 0; });
                    if ('untagged'.indexOf(low) === 0) choices.push({ name: '' });
                    starts.concat(inside).forEach(function (name) { choices.push({ name: name }); });
                    var exact = names.some(function (name) { return name.toLowerCase() === low; }) || low === 'untagged';
                    if (!exact) choices.push({ name: text, create: true });
                }
                var firstPick = choices.findIndex(function (choice) { return !choice.heading; });
                active = firstPick < 0 ? 0 : firstPick;
            }
            Shell.na_clear(list);
            var picks = 0;
            choices.forEach(function (choice, index) {
                if (choice.heading) { list.appendChild(Shell.na_el('div', 'na-menu__heading', choice.heading)); return; }
                picks += 1;
                list.appendChild(line(choice, index));
            });
            if (!picks) list.appendChild(Shell.na_el('div', 'na-tagpick__empty', 'No tags in this model yet: type a name to make one.'));
            var on = list.querySelector('.na-tagpick__item--active');
            if (on && on.scrollIntoView) on.scrollIntoView({ block: 'nearest' });
        }

        function step(delta) {
            var index = active;
            for (var guard = 0; guard < choices.length; guard++) {
                index = (index + delta + choices.length) % choices.length;
                if (!choices[index].heading) break;
            }
            active = index;
            draw(false);
        }

        input.addEventListener('input', function () { draw(true); });
        input.addEventListener('keydown', function (event) {
            event.stopPropagation();
            if (event.key === 'ArrowDown') { event.preventDefault(); step(1); }
            else if (event.key === 'ArrowUp') { event.preventDefault(); step(-1); }
            else if (event.key === 'Enter') { event.preventDefault(); if (choices[active] && !choices[active].heading) apply(choices[active]); }
            else if (event.key === 'Escape') { event.preventDefault(); View.na_close_menu(); document.getElementById('na-ol-tablewrap').focus({ preventScroll: true }); }
        });

        draw(true);
        menu.classList.remove('na-hidden');
        var width = menu.offsetWidth, height = menu.offsetHeight;
        menu.style.left = Math.max(4, Math.min(x, window.innerWidth - width - 6)) + 'px';
        menu.style.top  = Math.max(4, Math.min(y, window.innerHeight - height - 6)) + 'px';
        window.setTimeout(function () { input.focus(); }, 0);
    };

    function na_flag_items(pids) {
        var items = (Store.na_state().standards.flags || []).map(function (flag) {
            return { label: flag.label, colour: flag.colour, title: flag.meaning, action: function () { Bridge.na_call('flag', { pids: pids, flag: flag.id }); } };
        });
        items.push({ separator: true });
        items.push({ label: 'Flag With a Note\u2026', action: function () {
            Shell.na_prompt({ title: 'Flag for an Agent', label: 'What should the agent do?', multiline: true, confirm: 'Flag For Agent',
                              hint: 'The flag goes in the agent inbox with your note at the top of the thread.' },
                function (text) { Bridge.na_call('flag', { pids: pids, flag: 'for_agent', text: text }); });
        } });
        items.push({ label: 'Clear Flag', action: function () { Bridge.na_call('unflag', { pids: pids }); } });
        return items;
    }

    // FUNCTION | The Flag Menu for Given Objects (the Chat tab's header uses it)
    View.na_flag_menu_for = function (x, y, pids) {
        if (!pids || !pids.length) return;
        View.na_menu(x, y, na_flag_items(pids));
    };

    // FUNCTION | The Flag Menu for the Selected Rows
    View.na_flag_menu = function (x, y) {
        var pids = View.na_selected_pids();
        if (!pids.length) return Shell.na_set_status('Select rows first, then flag them.', 'warn');
        View.na_menu(x, y, na_flag_items(pids));
    };

    function na_prefix_items(pids) {
        var items = [];
        var lastCategory = null;
        (Store.na_state().standards.prefixes || []).forEach(function (entry) {
            if (entry.category !== lastCategory) { items.push({ heading: entry.category }); lastCategory = entry.category; }
            items.push({ label: entry.mode === 'face' ? 'Face: ' + entry.label : entry.label + (entry.mode === 'prefix' ? '__\u2026' : ''), colour: entry.colour, title: entry.meaning,
                         action: function () { Bridge.na_call('applyPrefix', { pids: pids, prefix: entry.id }); } });
        });
        items.push({ separator: true });
        items.push({ label: 'Take Standard Prefix Off', action: function () { Bridge.na_call('stripPrefix', { pids: pids }); } });
        return items;
    }

    function na_open_row_menu(x, y, item) {
        var pids = View.na_selected_pids();
        var row = Store.na_row(item.pid);
        var single = pids.length === 1;
        View.na_menu(x, y, [
            { label: 'Select in Model', action: function () { na_send_selection(false, true); } },
            { label: 'Zoom To', keys: 'Enter', action: function () { na_send_selection(true); } },
            { label: 'Reveal in Tree', disabled: Store.na_state().view !== 'tree' && !item.path, action: function () {
                Store.na_set_view('tree'); document.getElementById('na-ol-view').value = 'tree';
                Store.na_reveal(item.path); View.na_render();
                var index = Store.na_state().rows.findIndex(function (r) { return r.key === item.path.join('/'); });
                if (index >= 0) { V.sel = {}; V.sel[item.path.join('/')] = true; na_scroll_to(index); na_render_window(true); }
            } },
            { separator: true },
            { label: single ? 'Rename' : 'Rename ' + pids.length + ' Objects\u2026', keys: 'F2', action: function () { View.na_start_rename(item); } },
            { label: 'Find and Replace in Names\u2026', action: function () { View.na_replace_names(pids); } },
            { label: 'Quick Name', sub: na_prefix_items(pids) },
            { label: single ? 'Change Tag\u2026' : 'Change Tag of ' + pids.length + ' Objects\u2026', keys: 'T', action: function () { View.na_tag_picker(x, y, pids); } },
            { separator: true },
            { label: 'Flag', sub: na_flag_items(pids) },
            { label: 'Comment for the Agent\u2026', action: function () { View.na_comment(pids); } },
            { label: 'Open Thread', disabled: !single, action: function () { Shell.na_emit('focusThread', item.pid); } },
            { label: 'Open in Chat', disabled: !single, action: function () { Shell.na_emit('openChat', item.pid); } },
            { separator: true },
            { label: 'Copy for Agent', keys: 'Ctrl+C', action: function () { window.Na__AgentOutliner__Handoff.na_copy(pids); } },
            { label: 'Copy IDs', action: function () { Shell.na_copy(JSON.stringify(pids), 'Copied ' + pids.length + ' id' + (pids.length === 1 ? '' : 's') + '.'); } },
            { label: 'Copy Path', action: function () {
                var names = (item.path || [item.pid]).map(function (pid) { var r = Store.na_row(pid); return r ? r.dn : String(pid); });
                Shell.na_copy(names.join(' > ') + '  (id ' + item.pid + ')', 'Copied the path.');
            } },
            { separator: true },
            { label: row && row.h ? 'Show' : 'Hide', action: function () { Bridge.na_call('setHidden', { pids: pids, hidden: !(row && row.h) }); } },
            { label: row && row.l ? 'Unlock' : 'Lock', disabled: row && (row.k === 'i' || row.k === 's'), action: function () { Bridge.na_call('setLocked', { pids: pids, locked: !(row && row.l) }); } },
            { separator: true },
            { label: 'Open Everything Below', disabled: !item.hasKids, action: function () {
                var result = Store.na_expand_below(item, 5000); View.na_render();
                if (result.capped) Shell.na_set_status('Opened the first 5,000 rows below; open deeper rows one by one.', 'info');
            } },
            { label: 'Show Change History', disabled: !single, action: function () { Shell.na_emit('focusHistory', item.pid); } }
        ]);
    }

    // FUNCTION | Comment on the Selected Objects (one comment on each)
    View.na_comment = function (pids) {
        pids = pids || View.na_selected_pids();
        if (!pids.length) return Shell.na_set_status('Select rows first.', 'warn');
        Shell.na_prompt({
            title: pids.length === 1 ? 'Comment for the Agent' : 'Comment on ' + pids.length + ' Objects',
            label: 'Your comment', multiline: true, confirm: 'Send to Agent',
            hint: 'Ctrl+Enter sends. An agent reads it with agent_outliner {action: "inbox"} and answers in the same thread.',
            extra: 'Also flag ' + (pids.length === 1 ? 'it' : 'them') + ' For Agent'
        }, function (text, flagToo) {
            if (flagToo) Bridge.na_call('flag', { pids: pids, flag: 'for_agent', text: text });
            else Bridge.na_call('comment', { pids: pids, text: text });
        });
    };

    View.na_replace_names = function (pids) {
        Shell.na_prompt({ title: 'Find in Names', label: 'Find', confirm: 'Next', hint: 'Plain text, any case. Tick the box to use a pattern.', extra: 'Pattern (regular expression)' },
            function (find, pattern) {
                Shell.na_prompt({ title: 'Replace With', label: 'Replace "' + find + '" with', confirm: 'Replace', hint: 'Leave it empty to delete the text found.' },
                    function (replace) { Bridge.na_call('replaceNames', { pids: pids, find: find, replace: replace, pattern: pattern }); });
            });
    };

    function na_wire_menus() {
        document.addEventListener('mousedown', function (event) {
            var menu = document.getElementById('na-menu');
            if (!menu.classList.contains('na-hidden') && !menu.contains(event.target)) View.na_close_menu();
        });
        document.addEventListener('keydown', function (event) { if (event.key === 'Escape') View.na_close_menu(); });
        document.getElementById('na-ol-tablewrap').addEventListener('scroll', View.na_close_menu);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Toolbar, Quick Filters, Agent Bar
    // -------------------------------------------------------------------------

    function na_wire_toolbar() {
        var search = document.getElementById('na-ol-search');
        var timer = null;
        search.addEventListener('input', function () {
            if (timer) window.clearTimeout(timer);
            timer = window.setTimeout(function () { Store.na_set_search(search.value.trim()); View.na_render(); }, 140);
        });
        search.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') { event.preventDefault(); View.na_clear_filters(); }
            if (event.key === 'ArrowDown') { event.preventDefault(); document.getElementById('na-ol-tablewrap').focus(); na_select_index(0, 'single'); }
        });

        var view = document.getElementById('na-ol-view');
        Shell.na_fill_select(view, NA_VIEWS, 'tree');
        view.addEventListener('change', function () {
            Store.na_set_view(view.value);
            Shell.na_set_pref('view', view.value);
            View.na_render();
        });

        document.getElementById('na-ol-expand').addEventListener('click', function () {
            var result = Store.na_expand_below(null, 5000);
            View.na_render();
            if (result.capped) Shell.na_set_status('Opened the first 5,000 rows. Open deeper rows one by one (Alt+click a row\u2019s arrow opens all below it).', 'info');
        });
        document.getElementById('na-ol-collapse').addEventListener('click', function () { Store.na_collapse_all(); View.na_render(); });
        document.addEventListener('keydown', na_on_level_key);
        document.getElementById('na-ol-reveal').addEventListener('click', function () {
            V.echoUntil = 0;
            View.na_model_selection({ ids: Object.keys(Store.na_state().selectionIds).map(Number), active: Store.na_state().activePath }, true);
        });
        document.getElementById('na-ol-refresh').addEventListener('click', function () { Bridge.na_call('refresh', {}); });
        document.getElementById('na-ol-columns').addEventListener('click', function (event) {
            var rect = event.target.getBoundingClientRect();
            na_open_column_menu(rect.left, rect.bottom + 2);
        });
        document.getElementById('na-ol-search-help').addEventListener('click', function () {
            document.getElementById('na-search-help').classList.toggle('na-hidden');
        });
        document.getElementById('na-search-help-close').addEventListener('click', function () {
            document.getElementById('na-search-help').classList.add('na-hidden');
        });

        // The agent bar
        document.getElementById('na-ol-flag').addEventListener('click', function (event) {
            var rect = event.target.getBoundingClientRect();
            View.na_flag_menu(rect.left, rect.bottom + 2);
        });
        document.getElementById('na-ol-comment').addEventListener('click', function () { View.na_comment(); });
        document.getElementById('na-ol-tag').addEventListener('click', function (event) {
            var rect = event.target.getBoundingClientRect();
            View.na_tag_picker(rect.left, rect.bottom + 2, View.na_selected_pids());
        });
        document.getElementById('na-ol-copy-agent').addEventListener('click', function () { window.Na__AgentOutliner__Handoff.na_copy(View.na_selected_pids()); });
        document.getElementById('na-ol-copy-ids').addEventListener('click', function () {
            var pids = View.na_selected_pids();
            if (!pids.length) return Shell.na_set_status('Select rows first.', 'warn');
            Shell.na_copy(JSON.stringify(pids), 'Copied ' + pids.length + ' id' + (pids.length === 1 ? '' : 's') + '.');
        });
        document.getElementById('na-ol-model-thread').addEventListener('click', function () { Shell.na_emit('focusModelThread', null); });
        document.getElementById('na-ol-mark-seen').addEventListener('click', function () { Bridge.na_call('markChangesSeen', {}); });
    }

    // FUNCTION | Clear the Search and Every Quick Filter
    View.na_clear_filters = function () {
        document.getElementById('na-ol-search').value = '';
        Store.na_set_search('');
        Store.na_clear_quick();
        View.na_render();
    };

    function na_render_chips() {
        var host = Shell.na_clear(document.getElementById('na-ol-chips'));
        var S = Store.na_state();
        var lastFamily = null;
        Store.na_quick_chips().forEach(function (chip) {
            if (lastFamily && chip.family !== lastFamily) host.appendChild(Shell.na_el('span', 'na-chip-gap'));
            lastFamily = chip.family;
            var button = Shell.na_el('button', 'na-chip na-chip--' + chip.id + (S.quick[chip.id] ? ' na-chip--on' : ''), chip.label);
            button.type = 'button';
            button.title = chip.title;
            button.addEventListener('click', function () { Store.na_toggle_quick(chip.id); View.na_render(); });
            host.appendChild(button);
        });
        if (Store.na_filtering()) {
            host.appendChild(Shell.na_button('Clear', 'na-chip na-chip--clear', function () { View.na_clear_filters(); }, 'Clear the search and filters (Esc)'));
        }
        Shell.na_text('na-ol-match-count', Store.na_filtering() ? (S.matchCount + ' match' + (S.matchCount === 1 ? '' : 'es')) : '');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | The Quick Name Panel (0.1.15)
    // -------------------------------------------------------------------------
    // Adam: "move the quick naming system from the top into a new left popout
    // menu, that format is too inneffcient and not scalable havbing it at the
    // top". The Name button on the rail (or Q) pops the panel out on the
    // table's left: the standard names in one column under their categories
    // (each folds away, remembered), a filter, the Front faces compass, Strip
    // Prefix and Edit Names. One click names the selected rows, as before.
    // Open or shut is remembered (the old bar's quickNameOpen preference).

    // FUNCTION | Open or Close the Panel
    // @param open     {boolean}
    // @param remember {boolean} false when restoring the remembered state
    View.na_set_quick_name_open = function (open, remember) {
        V.quickNameOpen = !!open;
        document.getElementById('na-qn-panel').classList.toggle('na-hidden', !V.quickNameOpen);
        var rail = document.getElementById('na-qn-rail');
        rail.setAttribute('aria-pressed', V.quickNameOpen ? 'true' : 'false');
        rail.title = (V.quickNameOpen ? 'Close Quick Name' : 'Quick Name: give the selected rows a standard name') + ' (Q)';
        if (remember !== false) Shell.na_set_pref('quickNameOpen', V.quickNameOpen);
        if (V.quickNameOpen) View.na_render_quick_name();
        window.setTimeout(function () { na_render_window(true); }, 0);               // <-- The table narrowed or widened
    };

    // The text a name button shows: CAD__FrontElevation, REF__, __Front__South__
    function na_qn_text(entry) {
        if (entry.mode === 'face') {
            var cardinal = Store.na_cardinal_for(entry.label);
            return '__' + entry.label + (cardinal ? '__' + cardinal : '') + '__';
        }
        return entry.label + (entry.mode === 'prefix' ? '__' : '');
    }

    function na_qn_item(entry) {
        var isFace = entry.mode === 'face';
        var cardinal = isFace ? Store.na_cardinal_for(entry.label) : '';
        var item = Shell.na_el('button', 'na-qn-item');
        item.type = 'button';
        item.setAttribute('role', 'listitem');
        item.style.setProperty('--na-qn', entry.colour || '#64748b');
        item.appendChild(Shell.na_el('span', 'na-qn-item__swatch'));
        item.appendChild(Shell.na_el('span', 'na-qn-item__label', na_qn_text(entry)));
        item.title = (isFace ? 'Set the elevation face in the selected names to ' + entry.label + (cardinal ? '__' + cardinal : '') + ' (swapped in place, or put before a trailing number)'
                             : entry.mode === 'replace' ? 'Name the selected objects exactly ' + entry.label : 'Put ' + entry.label + '__ in front of their names') +
                     '.' + (entry.meaning ? '\n' + entry.meaning : '');
        item.addEventListener('click', function () {
            var pids = View.na_selected_pids();
            if (!pids.length) return Shell.na_set_status('Select the groups to name first (in the table, or click them in the model).', 'warn');
            Bridge.na_call('applyPrefix', { pids: pids, prefix: entry.id });
        });
        return item;
    }

    // FUNCTION | Draw the Panel's Names (only while it is open)
    View.na_render_quick_name = function () {
        if (!V.quickNameOpen) return;
        var list = Shell.na_clear(document.getElementById('na-qn-list'));
        var filterText = (document.getElementById('na-qn-filter').value || '').trim();
        var filter = filterText.toLowerCase();
        var prefixes = (Store.na_state().standards || {}).prefixes || [];
        var shut = Shell.na_get_pref('qnCollapsed', {}) || {};
        var order = [];
        var byCategory = {};
        prefixes.forEach(function (entry) {
            var category = entry.category || 'Other';
            if (filter && (na_qn_text(entry) + ' ' + category + ' ' + (entry.meaning || '')).toLowerCase().indexOf(filter) < 0) return;
            if (!byCategory[category]) { byCategory[category] = []; order.push(category); }
            byCategory[category].push(entry);
        });
        if (!order.length) {
            list.appendChild(Shell.na_el('div', 'na-qn-empty', prefixes.length ? 'No standard name matches \u201c' + filterText + '\u201d.' : 'No standard names yet: Edit Names adds them.'));
        }
        order.forEach(function (category) {
            var closed = !filter && !!shut[category];                                  // <-- A filter shows every match
            var head = Shell.na_el('button', 'na-qn-group' + (closed ? ' na-qn-group--shut' : ''));
            head.type = 'button';
            head.setAttribute('aria-expanded', closed ? 'false' : 'true');
            head.title = (closed ? 'Show' : 'Fold away') + ' the ' + category + ' names';
            head.appendChild(Shell.na_el('span', 'na-qn-group__twisty', closed ? '\u25b8' : '\u25be'));
            head.appendChild(Shell.na_el('span', 'na-qn-group__label', category));
            head.appendChild(Shell.na_el('span', 'na-qn-group__count', String(byCategory[category].length)));
            head.addEventListener('click', function () {
                var next = {};
                var now = Shell.na_get_pref('qnCollapsed', {}) || {};
                Object.keys(now).forEach(function (key) { if (now[key]) next[key] = true; });
                if (next[category]) delete next[category]; else next[category] = true;
                Shell.na_set_pref('qnCollapsed', next);
                View.na_render_quick_name();
            });
            list.appendChild(head);
            if (closed) return;
            byCategory[category].forEach(function (entry) { list.appendChild(na_qn_item(entry)); });
        });
        na_render_qn_target();
        na_render_qn_orient();
    };

    function na_render_qn_target() {
        var target = document.getElementById('na-qn-target');
        if (!target || !V.quickNameOpen) return;
        var count = View.na_selected_pids().length;
        target.textContent = count ? 'Names the ' + (count === 1 ? 'selected row' : count + ' selected rows')
                                   : 'Select rows (or objects in SketchUp), then click a name';
        target.classList.toggle('na-qn-panel__target--none', !count);
    }

    // Which way the model's Front faces in the real world: the Front__South cardinal (Adam, 11-Nov-2026)
    function na_render_qn_orient() {
        var orient = document.getElementById('na-qn-orient');
        var front = (Store.na_state().model || {}).front_faces || '';
        Shell.na_fill_select(orient, [{ value: '', label: 'Front faces: not set' }].concat(Store.na_cardinals().map(function (c) { return { value: c, label: 'Front faces ' + c }; })), front);
        orient.disabled = !Store.na_state().model;
    }

    function na_wire_quick_name() {
        document.getElementById('na-qn-rail').addEventListener('click', function () { View.na_set_quick_name_open(!V.quickNameOpen); });
        document.getElementById('na-qn-close').addEventListener('click', function () { View.na_set_quick_name_open(false); });
        var filter = document.getElementById('na-qn-filter');
        filter.addEventListener('input', function () { View.na_render_quick_name(); });
        filter.addEventListener('keydown', function (event) {
            event.stopPropagation();
            if (event.key === 'Escape') { event.preventDefault(); filter.value = ''; View.na_render_quick_name(); }
            if (event.key === 'Enter') {                                                // <-- Enter names the selection with the only (or first) match
                event.preventDefault();
                var first = document.querySelector('#na-qn-list .na-qn-item');
                if (first) first.click();
            }
        });
        document.getElementById('na-qn-orient').addEventListener('change', function (event) { Bridge.na_call('setFrontFaces', { cardinal: event.target.value }); });
        document.getElementById('na-qn-strip').addEventListener('click', function () {
            var pids = View.na_selected_pids();
            if (!pids.length) return Shell.na_set_status('Select rows first.', 'warn');
            Bridge.na_call('stripPrefix', { pids: pids });
        });
        document.getElementById('na-qn-edit').addEventListener('click', function () { Shell.na_activate_tab('configure'); });
        Shell.na_on('uiSelection', na_render_qn_target);
        document.addEventListener('keydown', function (event) {                       // <-- Q, anywhere on the Outliner tab but a text field
            if (event.ctrlKey || event.metaKey || event.altKey || event.defaultPrevented) return;
            if (event.key !== 'q' && event.key !== 'Q') return;
            var panel = document.getElementById('na-tab-outliner');
            if (!panel || panel.classList.contains('na-hidden')) return;
            var target = event.target;
            if (target && (/INPUT|TEXTAREA|SELECT/.test(target.tagName) || target.isContentEditable)) return;
            event.preventDefault();
            View.na_set_quick_name_open(!V.quickNameOpen);
            if (V.quickNameOpen) window.setTimeout(function () { filter.focus(); }, 0);
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Footer
    // -------------------------------------------------------------------------

    function na_render_footer() {
        var S = Store.na_state();
        var total = Object.keys(S.ents).length;
        var flagged = 0, unread = 0, waiting = 0, latest = null;
        Object.keys(S.ents).forEach(function (pid) {
            var row = S.ents[pid];
            if (row.nf) flagged += 1;
            unread += row.nu || 0;
            waiting += row.nw || 0;
            var change = Store.na_change(pid);
            if (change && change.ever && (!latest || change.latest > latest.latest)) latest = change;
        });
        var modelNotes = S.modelNotes;
        if (modelNotes && modelNotes.entries) {
            modelNotes.entries.forEach(function (entry) { if (entry.new_for_adam) unread += 1; });
        }
        var parts = [total.toLocaleString() + ' objects'];
        if (Store.na_filtering() || S.view !== 'tree') parts.push(S.matchCount.toLocaleString() + ' listed');
        var selected = View.na_selected_pids().length;
        if (selected) parts.push(selected + ' selected');
        if (flagged) parts.push(flagged + ' flagged');
        if (latest) parts.push('last change ' + Shell.na_ago(latest.latest) + ' by ' + (latest.by === 'agent' ? 'an agent' : 'you'));
        if (S.truncated) parts.push('showing the first 60,000 rows');
        Shell.na_text('na-ol-footer-counts', parts.join('  \u00b7  '));

        var inbox = document.getElementById('na-ol-inbox');
        Shell.na_clear(inbox);
        if (unread) {
            var u = Shell.na_button(unread + ' unread from agents', 'na-inbox-chip na-inbox-chip--agent', function () {
                if (!Store.na_state().quick.unread) Store.na_toggle_quick('unread');
                View.na_render();
            }, 'Replies an agent wrote that you have not read: click to list them');
            inbox.appendChild(u);
        }
        if (waiting) {
            var w = Shell.na_button(waiting + ' waiting for agents', 'na-inbox-chip na-inbox-chip--user', function () {
                if (!Store.na_state().quick.waiting) Store.na_toggle_quick('waiting');
                View.na_render();
            }, 'Your comments and flags no agent has read yet');
            inbox.appendChild(w);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Channels and Init
    // -------------------------------------------------------------------------

    function na_wire_channels() {
        Shell.na_on('state', function (state) {
            Store.na_set_state(state);
            var ui = state.ui || {};
            if (!V.columnsRestored) { V.columnsRestored = true; na_load_columns(); }              // <-- Saved columns arrive with the first state, after init
            if (ui.view && document.getElementById('na-ol-view').value !== ui.view && !V.viewRestored) {
                V.viewRestored = true;
                document.getElementById('na-ol-view').value = ui.view;
                Store.na_set_view(ui.view);
            }
            if (Array.isArray(ui.sort) && !V.sortRestored) { V.sortRestored = true; Store.na_state().sort = ui.sort; }
            if (!V.quickNameRestored) { V.quickNameRestored = true; View.na_set_quick_name_open(ui.quickNameOpen !== false, false); }
            else View.na_render_quick_name();
            na_render_switches();
            View.na_render();
        });
        Shell.na_on('snapshot', function (payload) {
            Store.na_load_snapshot(payload);
            V.sel = {};
            View.na_render();
            View.na_render_quick_name();                                                // <-- Front faces may have changed (setFrontFaces sends a snapshot)
            var note = payload.tracking && payload.tracking.capped ? ' Images and section planes were not all scanned (very large model).' : '';
            if (payload.build_ms > 1500) Shell.na_set_status('Read ' + Object.keys(payload.ents || {}).length + ' objects in ' + (payload.build_ms / 1000).toFixed(1) + ' s.' + note, 'info');
        });
        Shell.na_on('delta', function (delta) { Store.na_apply_delta(delta); View.na_render(); });
        Shell.na_on('tags', function (tags) { Store.na_set_tags(tags); View.na_render(); });
        Shell.na_on('selection', function (selection) { View.na_model_selection(selection); });
        Shell.na_on('seen', function (seen) { Store.na_set_seen(seen); View.na_render(); });
        Shell.na_on('tab', function (tab) { if (tab === 'outliner') window.setTimeout(function () { na_render_window(true); }, 0); });
        window.addEventListener('resize', function () { na_render_window(true); });
        window.setInterval(function () {                                                    // <-- Ages move on: the colours fade without a push
            if (!document.getElementById('na-tab-outliner').classList.contains('na-hidden')) { Store.na_touch(); View.na_render(); }
        }, 60000);
    }

    function na_init() {
        Shell  = window.Na__AgentOutliner__Shell;
        Store  = window.Na__AgentOutliner__Store;
        Bridge = window.Na__AgentOutliner__Bridge;
        na_load_columns();
        na_wire_header();
        na_wire_body();
        na_wire_toolbar();
        na_wire_menus();
        na_wire_switches();
        na_wire_quick_name();
        na_wire_channels();
        na_render_switches();
        View.na_render();
    }

    window.Na__AgentOutliner__View = View;
    window.Na__AgentOutliner__Shell.na_on('init', na_init);
})();

// =============================================================================
// END OF FILE
// =============================================================================
