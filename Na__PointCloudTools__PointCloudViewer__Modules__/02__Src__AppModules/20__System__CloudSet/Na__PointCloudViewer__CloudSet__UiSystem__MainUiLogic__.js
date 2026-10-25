// =============================================================================
// NA POINT CLOUD VIEWER - CLOUD SET - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__CloudSet__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__CloudSet
// PURPOSE    : Which point cloud the tabs work on (v0.10.0), shown three ways:
//                the cloud bar   under the tab strip, on every tab: one chip
//                                per cloud. Its eye shows or hides the cloud;
//                                a click makes it the cloud every tab works on.
//                the cloud list  the View tab's Point Clouds card. The active
//                                cloud's row opens with its file, position and
//                                buttons (Reload, Locate, Zoom, Unload, Rename,
//                                Remove); drag a row by its grip to reorder.
//                cloud tags      any element with data-na-cloud-tag shows the
//                                active cloud's name in its colour when the
//                                model holds more than one cloud. Elements with
//                                data-na-multi-only show only then.
//
// STATE: everything shown comes from state.clouds (Ruby). This file only
//   remembers what the user is in the middle of: a name being typed, an open
//   colour palette, a Remove waiting for its second click.
//
// =============================================================================

(function () {
    'use strict';

    var CloudSet = {};
    var Shell  = window.Na__PointCloudViewer__Shell;
    var Bridge = window.Na__PointCloudViewer__Bridge;
    var DragReorder = window.Na__PointCloudViewer__DragReorder;

    var NA_CONFIRM_MS = 3000;
    var NA_SVG = 'http://www.w3.org/2000/svg';

    var na_clouds        = null;    // last state.clouds
    var na_renaming      = null;    // { id, text } while a name is being typed
    var na_palette_id    = null;    // cloud whose colour palette is open
    var na_confirm_id    = null;    // cloud waiting for a second Remove click
    var na_confirm_timer = null;
    var na_sorter        = null;    // drag to reorder on the list
    var na_list_waiting  = false;   // a repaint held back while a row is being dragged

    // -------------------------------------------------------------------------
    // REGION | Small Builders
    // -------------------------------------------------------------------------

    function na_button(label, className, handler, title) {
        var button = Shell.na_el('button', className, label);
        button.type = 'button';
        if (title) button.title = title;
        button.addEventListener('click', function (event) { event.stopPropagation(); handler(); });
        return button;
    }

    // An eye drawn in SVG (no icon font): open, or closed with a stroke through it.
    function na_eye(open) {
        var svg = document.createElementNS(NA_SVG, 'svg');
        svg.setAttribute('viewBox', '0 0 16 16');
        svg.setAttribute('class', 'na-eye' + (open ? '' : ' na-eye--closed'));
        svg.setAttribute('aria-hidden', 'true');
        var outline = document.createElementNS(NA_SVG, 'path');
        outline.setAttribute('d', 'M1.5 8C3.1 5.1 5.3 3.6 8 3.6S12.9 5.1 14.5 8C12.9 10.9 10.7 12.4 8 12.4S3.1 10.9 1.5 8Z');
        svg.appendChild(outline);
        var pupil = document.createElementNS(NA_SVG, 'circle');
        pupil.setAttribute('cx', '8');
        pupil.setAttribute('cy', '8');
        pupil.setAttribute('r', '2.1');
        svg.appendChild(pupil);
        if (!open) {
            var stroke = document.createElementNS(NA_SVG, 'path');
            stroke.setAttribute('class', 'na-eye__stroke');
            stroke.setAttribute('d', 'M2.8 13.2L13.2 2.8');
            svg.appendChild(stroke);
        }
        return svg;
    }

    function na_eye_button(row, className) {
        var eye = na_button('', className, function () {
            Bridge.na_call('cloud_set_visible', { id: row.id, visible: !row.visible });
        }, (row.visible ? 'Hide ' : 'Show ') + row.name + '. Only this view changes; nothing is written to the model.');
        eye.setAttribute('aria-pressed', row.visible ? 'true' : 'false');
        eye.setAttribute('aria-label', (row.visible ? 'Hide ' : 'Show ') + row.name);
        eye.appendChild(na_eye(row.visible));
        return eye;
    }

    function na_paint_colour(element, row) {
        element.style.setProperty('--na-cloud-colour', row.colour || '#888888');
    }

    function na_multi() {
        return !!na_clouds && (na_clouds.count || 0) > 1;
    }

    function na_active_row() {
        var rows = (na_clouds && na_clouds.list) || [];
        return rows.filter(function (row) { return row.isActive; })[0] || null;
    }

    function na_reloadable(rows) {
        return rows.filter(function (row) { return row.needsReload && row.foundPath; });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Words
    // -------------------------------------------------------------------------

    // [text, modifier] for a cloud's status tag.
    function na_status(row) {
        if (!row.loaded) return row.foundPath ? ['Not loaded', 'warn'] : ['LAS not found', 'danger'];
        if (row.recordState === 'unsaved') return ['Not in the model', 'warn'];
        if (row.namesOther || row.staleEngine) return ['Reload to update', 'warn'];
        return row.visible ? ['Shown', 'ok'] : ['Hidden', ''];
    }

    function na_detail(row) {
        var unit = String(row.unitLabel || '').toLowerCase();
        var text = (row.fileName || row.name) + ': ' + (row.pointsText || '0') + ' points' + (unit ? ' in ' + unit : '');
        return row.sizeText ? text + ', ' + row.sizeText : text;
    }

    function na_share_text(row) {
        if (!row.loaded || !row.visible || row.share === null || row.share === undefined) return '';
        if (row.share >= row.totalPoints) return 'Drawing all ' + Shell.na_format_int(row.totalPoints) + ' of its points.';
        return 'Drawing ' + Shell.na_format_int(row.share) + ' of its ' + Shell.na_format_int(row.totalPoints) + ' points from the shared budget.';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Cloud Bar (under the tab strip)
    // -------------------------------------------------------------------------

    function na_chip_mark(row) {
        if (!row.loaded) return row.foundPath ? 'not loaded' : 'not found';
        if (row.recordState === 'unsaved') return 'not saved';
        if (row.namesOther || row.staleEngine) return 'reload';
        return '';
    }

    function na_chip(row) {
        var chip = Shell.na_el('div', 'na-cloud-chip' + (row.isActive ? ' na-cloud-chip--active' : '') +
                                      (row.visible ? '' : ' na-cloud-chip--hidden') + (row.loaded ? '' : ' na-cloud-chip--unloaded'));
        na_paint_colour(chip, row);
        chip.appendChild(na_eye_button(row, 'na-cloud-chip__eye'));
        var main = na_button('', 'na-cloud-chip__main', function () {
            if (!row.isActive) Bridge.na_call('cloud_activate', { id: row.id });
        }, row.isActive ? 'Every tab is working on ' + row.name : 'Work on ' + row.name + ' in every tab');
        main.setAttribute('aria-pressed', row.isActive ? 'true' : 'false');
        main.appendChild(Shell.na_el('span', 'na-cloud-dot'));
        main.appendChild(Shell.na_el('span', 'na-cloud-chip__name', row.name));
        var mark = na_chip_mark(row);
        if (mark) main.appendChild(Shell.na_el('span', 'na-cloud-chip__mark', mark));
        chip.appendChild(main);
        return chip;
    }

    function na_add_chip(clouds) {
        var full = (clouds.count || 0) >= (clouds.maxClouds || 10);
        var add = na_button('+', 'na-cloud-chip__add', function () {
            Shell.na_set_status('Choose a LAS or LAZ file to add...', 'info');
            Bridge.na_call('las_pick_file', {});
        }, full ? 'This model holds ' + clouds.count + ' point clouds, the most it can hold. Remove one on the View tab first.'
                : 'Add a point cloud to this model (Import LAS / LAZ)');
        add.setAttribute('aria-label', 'Add a point cloud');
        add.disabled = full || !!clouds.readonly;
        return add;
    }

    function na_render_bar(clouds) {
        var bar = document.getElementById('na-cloud-bar');
        if (!bar) return;
        var rows = clouds.list || [];
        bar.classList.toggle('na-hidden', !rows.length);
        bar.innerHTML = '';
        if (!rows.length) return;
        bar.appendChild(Shell.na_el('span', 'na-cloud-bar__label', rows.length > 1 ? 'Working on' : 'Cloud'));
        rows.forEach(function (row) { bar.appendChild(na_chip(row)); });
        bar.appendChild(na_add_chip(clouds));
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Cloud List (View tab)
    // -------------------------------------------------------------------------

    function na_ask_remove(row) {
        if (na_confirm_id === row.id) {
            na_clear_confirm();
            Bridge.na_call('cloud_remove', { id: row.id });
            return;
        }
        na_clear_confirm();
        na_confirm_id = row.id;
        na_confirm_timer = window.setTimeout(function () {
            na_clear_confirm();
            na_render_list();
        }, NA_CONFIRM_MS);
        na_render_list();
    }

    function na_clear_confirm() {
        if (na_confirm_timer) window.clearTimeout(na_confirm_timer);
        na_confirm_timer = null;
        na_confirm_id = null;
    }

    function na_finish_rename(save) {
        if (!na_renaming) return;
        var renaming = na_renaming;
        na_renaming = null;
        if (save && renaming.text.trim()) {
            Bridge.na_call('cloud_rename', { id: renaming.id, name: renaming.text.trim() });
        } else {
            na_render_list();
        }
    }

    function na_rename_input(row) {
        var input = Shell.na_el('input', 'naInput na-cloud-row__rename');
        input.type = 'text';
        input.maxLength = 60;
        input.value = na_renaming.text;
        input.setAttribute('aria-label', 'New name for ' + row.name);
        input.addEventListener('input', function () { na_renaming.text = input.value; });
        input.addEventListener('keydown', function (event) {
            if (event.key === 'Enter')  { na_finish_rename(true); }
            if (event.key === 'Escape') { na_finish_rename(false); }
        });
        window.setTimeout(function () {
            if (document.activeElement !== input) { input.focus(); input.select(); }
        }, 0);
        return input;
    }

    function na_palette(row) {
        var strip = Shell.na_el('div', 'na-cloud-palette');
        strip.appendChild(Shell.na_el('span', 'na-cloud-palette__label', 'Colour'));
        ((na_clouds && na_clouds.palette) || []).forEach(function (hex) {
            var chosen = String(hex).toLowerCase() === String(row.colour).toLowerCase();
            var swatch = na_button('', 'na-cloud-swatch' + (chosen ? ' na-cloud-swatch--chosen' : ''), function () {
                na_palette_id = null;
                if (!chosen) Bridge.na_call('cloud_set_colour', { id: row.id, colour: hex });
                na_render_list();
            }, chosen ? 'The colour of ' + row.name + ' now' : 'Use this colour for ' + row.name);
            swatch.style.setProperty('--na-cloud-colour', hex);
            swatch.setAttribute('aria-label', 'Colour ' + hex);
            strip.appendChild(swatch);
        });
        strip.appendChild(Shell.na_el('span', 'na-cloud-palette__note', 'Used by Cloud Colour (View tab) and the cloud bar. Saved in the model.'));
        return strip;
    }

    function na_row_main(row, sortable) {
        var main = Shell.na_el('div', 'na-cloud-row__main');
        main.appendChild(sortable ? DragReorder.na_grip(row.name) : Shell.na_el('span', 'na-grip-spacer'));
        main.appendChild(na_eye_button(row, 'na-cloud-row__eye'));
        var swatch = na_button('', 'na-cloud-row__swatch', function () {
            na_palette_id = na_palette_id === row.id ? null : row.id;
            na_render_list();
        }, 'Change the colour of ' + row.name);
        swatch.setAttribute('aria-label', 'Change the colour of ' + row.name);
        swatch.disabled = !!(na_clouds && na_clouds.readonly) || row.recordState === 'unsaved';
        main.appendChild(swatch);

        if (na_renaming && na_renaming.id === row.id) {
            main.appendChild(na_rename_input(row));
            var actions = Shell.na_el('div', 'na-scene__actions');
            actions.appendChild(na_button('Save', 'na-scene-action na-scene-action--primary', function () { na_finish_rename(true); }));
            actions.appendChild(na_button('Cancel', 'na-scene-action', function () { na_finish_rename(false); }));
            main.appendChild(actions);
            return main;
        }
        var name = na_button(row.name, 'na-cloud-row__name', function () {
            if (!row.isActive) Bridge.na_call('cloud_activate', { id: row.id });
        }, row.isActive ? 'Every tab is working on ' + row.name : 'Work on ' + row.name + ' in every tab');
        main.appendChild(name);
        var status = na_status(row);
        main.appendChild(Shell.na_el('span', 'na-cloud-status' + (status[1] ? ' na-cloud-status--' + status[1] : ''), status[0]));
        return main;
    }

    // The open row of the active cloud: where its LAS is, its position, and its buttons.
    function na_row_open(row) {
        var wrap = Shell.na_el('div', 'na-cloud-row__open');
        var share = na_multi() ? na_share_text(row) : '';
        if (share) wrap.appendChild(Shell.na_el('p', 'na-cloud-row__line', share));
        // Unloaded: what Reload will do. Loaded: whether the Transform tab may move it.
        var position = row.loaded ? (row.locked ? 'Its position is locked.' : 'Its position is unlocked: the Transform tab can move it.') : row.positionText;
        if (position && row.recordState !== 'unsaved') wrap.appendChild(Shell.na_el('p', 'na-cloud-row__line', position));
        if (row.derivedFrom) wrap.appendChild(Shell.na_el('p', 'na-cloud-row__line', 'A ' + (row.derivedHow || 'cleaned') + ' copy of ' + row.derivedFrom + ', which is kept unchanged.'));
        if (row.recordState === 'unsaved') {
            wrap.appendChild(Shell.na_el('p', 'na-note', 'This cloud is on screen but not saved in the model (an Undo took it out). Unload it, or import its LAS again to add it back.'));
        } else if (row.staleEngine) {
            wrap.appendChild(Shell.na_el('p', 'na-note', 'The point cloud engine was updated after this cloud was loaded, so its points are gone from memory. Reload brings it back (from its point cache, quickly).'));
        } else if (row.namesOther) {
            wrap.appendChild(Shell.na_el('p', 'na-note', 'The model now names a different LAS for this cloud than the one on screen. Reload uses the one the model names.'));
        }
        if (row.needsReload && row.recordState !== 'unsaved') {
            var path = Shell.na_el('p', 'na-path na-link-path' + (row.foundPath ? '' : ' na-link-path--missing'),
                                   row.foundPath ? 'Found: ' + row.foundPath : 'Not found at: ' + (row.lastPath || '') + '. Use Locate LAS to point to it.');
            wrap.appendChild(path);
        }
        if (row.note) wrap.appendChild(Shell.na_el('p', 'na-note', row.note));

        var readonly = !!(na_clouds && na_clouds.readonly);
        var actions = Shell.na_el('div', 'na-cloud-row__actions');
        if (row.needsReload && row.recordState !== 'unsaved') {
            var reload = na_button('Reload', 'naButton na-button--small', function () {
                Bridge.na_call_after_paint('cloud_reload', { id: row.id }, 'Reloading ' + row.name, 'Checking the LAS file...');
            }, 'Reads the LAS (or its point cache) and puts the cloud back where the model says');
            reload.disabled = !row.foundPath;
            actions.appendChild(reload);
            actions.appendChild(na_button('Locate LAS…', 'naButtonSecondary na-button--small', function () {
                Bridge.na_call('cloud_locate', { id: row.id });
            }, 'Point to this cloud\'s LAS file if it has moved'));
        }
        if (row.loaded) {
            actions.appendChild(na_button('Zoom To', 'naButtonSecondary na-button--small', function () {
                Bridge.na_call('cloud_zoom', { id: row.id });
            }, 'Frames this cloud, or its clipped part while its clipping is on'));
            actions.appendChild(na_button('Unload', 'naButtonSecondary na-button--small', function () {
                Bridge.na_call('cloud_unload', { id: row.id });
            }, 'Frees its memory. The model keeps the cloud; Reload brings it back.'));
        }
        if (!readonly && row.recordState !== 'unsaved') {
            actions.appendChild(na_button('Rename', 'naButtonSecondary na-button--small', function () {
                na_clear_confirm();
                na_renaming = { id: row.id, text: row.name };
                na_render_list();
            }));
            var confirming = na_confirm_id === row.id;
            var remove = na_button(confirming ? 'Click again to remove (Undo restores it)' : 'Remove', 'naButtonSecondary na-button--small' + (confirming ? ' na-button--danger' : ''), function () {
                na_ask_remove(row);
            }, 'Takes this cloud out of the model. Its LAS file and point cache are untouched; Edit, Undo puts it back.');
            actions.appendChild(remove);
        }
        if (actions.childNodes.length) wrap.appendChild(actions);
        return wrap;
    }

    function na_row(row, sortable) {
        var el = Shell.na_el('div', 'na-cloud-row' + (row.isActive ? ' na-cloud-row--active' : '') + (row.visible ? '' : ' na-cloud-row--hidden'));
        el.setAttribute('data-na-sort-id', row.id);
        na_paint_colour(el, row);
        el.appendChild(na_row_main(row, sortable));
        el.appendChild(Shell.na_el('p', 'na-cloud-row__detail', na_detail(row)));
        if (na_palette_id === row.id) el.appendChild(na_palette(row));
        if (row.isActive) el.appendChild(na_row_open(row));
        return el;
    }

    function na_sortable(rows) {
        return rows.length > 1 && !na_renaming && !(na_clouds && na_clouds.readonly) &&
               rows.every(function (row) { return row.recordState === 'saved' || row.recordState === 'legacy'; });
    }

    function na_render_list() {
        var list = document.getElementById('na-cloud-list');
        if (!list || !na_clouds) return;
        // A row is being dragged: the list repaints when it is dropped
        if (na_sorter && na_sorter.na_is_dragging()) { na_list_waiting = true; return; }
        list.innerHTML = '';
        var rows = na_clouds.list || [];
        var sortable = na_sortable(rows);
        rows.forEach(function (row) { list.appendChild(na_row(row, sortable)); });
        list.classList.toggle('na-hidden', !rows.length);
        if (na_sorter) na_sorter.na_after_render();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Point Clouds Card (header, buttons, hint)
    // -------------------------------------------------------------------------

    function na_render_card(state) {
        var clouds = na_clouds;
        var rows = clouds.list || [];
        var count = clouds.count || 0;
        var max = clouds.maxClouds || 10;
        Shell.na_text('na-clouds-count', count > 1 ? count + ' of ' + max + ' clouds' : '');

        var problem = document.getElementById('na-clouds-problem');
        var problemText = clouds.problem || (clouds.readonly ? 'These point clouds were saved by a newer version of the viewer, so they are shown but never changed here. Update the viewer on this computer.' : '');
        problem.textContent = problemText;
        problem.classList.toggle('na-hidden', !problemText);

        var importButton = document.getElementById('na-view-import-las');
        importButton.textContent = count ? 'Add Point Cloud…' : 'Import LAS / LAZ…';
        importButton.disabled = count >= max || !!clouds.readonly;
        importButton.title = count >= max
            ? 'This model holds ' + count + ' point clouds, the most it can hold. Remove one first.'
            : 'Adds a LAS or LAZ as a cloud of this model. A LAZ (from Polycam and others) is first decompressed, losslessly, into a new LAS next to it.';

        var reloadable = na_reloadable(rows);
        var waiting = rows.filter(function (row) { return row.needsReload && row.recordState !== 'unsaved'; });
        // Primary while nothing is loaded: Reload is then the next thing to do
        var reloadAll = document.getElementById('na-clouds-reload-all');
        reloadAll.className = (clouds.loadedCount ? 'naButtonSecondary' : 'naButton') + (waiting.length ? '' : ' na-hidden');
        reloadAll.textContent = count === 1 ? 'Reload Point Cloud' : (waiting.length === count ? 'Reload All' : 'Reload ' + waiting.length + ' Not Loaded');
        reloadAll.disabled = !reloadable.length;

        var shown = rows.filter(function (row) { return row.loaded && row.visible; });
        var zoom = document.getElementById('na-view-zoom');
        zoom.textContent = shown.length > 1 ? 'Zoom to Clouds' : 'Zoom to Cloud';
        zoom.disabled = !shown.length;

        Shell.na_text('na-clouds-hint', !count
            ? 'Import a LAS or LAZ to start. The LAS file is only ever read, never changed. The model remembers which LAS each cloud uses, where it sits, its clip box and its look; Reload brings the points back next time.'
            : (count > 1
                ? 'Each cloud keeps its own LAS link, position, clip box and look in this model, and its own point cache on this computer. Click a cloud to work on it in every tab; its eye shows or hides it. Nothing loads until you press Reload.'
                : 'The model remembers which LAS this cloud uses, where it sits, its clip box and its look. Add Point Cloud brings in another one (an exterior scan, say) to align with it. Nothing loads until you press Reload.'));
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Cloud Tags (the active cloud named on other tabs)
    // -------------------------------------------------------------------------

    function na_render_tags() {
        var multi = na_multi();
        var active = na_active_row();
        Array.prototype.forEach.call(document.querySelectorAll('[data-na-cloud-tag]'), function (tag) {
            var show = multi && !!active;
            tag.classList.toggle('na-hidden', !show);
            tag.innerHTML = '';
            if (!show) return;
            na_paint_colour(tag, active);
            tag.title = 'This card works on ' + active.name + '. Choose another cloud in the bar above.';
            tag.appendChild(Shell.na_el('span', 'na-cloud-dot'));
            tag.appendChild(Shell.na_el('span', 'na-cloud-tag__name', active.name));
        });
        Array.prototype.forEach.call(document.querySelectorAll('[data-na-multi-only]'), function (element) {
            element.classList.toggle('na-hidden', !multi);
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render From State
    // -------------------------------------------------------------------------

    CloudSet.na_render = function (state) {
        if (!state || !state.clouds) return;
        na_clouds = state.clouds;
        var ids = (na_clouds.list || []).map(function (row) { return row.id; });
        if (na_renaming && ids.indexOf(na_renaming.id) === -1) na_renaming = null;
        if (na_palette_id && ids.indexOf(na_palette_id) === -1) na_palette_id = null;
        if (na_confirm_id && ids.indexOf(na_confirm_id) === -1) na_clear_confirm();
        na_render_bar(na_clouds);
        na_render_list();
        na_render_card(state);
        na_render_tags();
    };

    // The active cloud's row of the last state, or null (other tabs may ask).
    CloudSet.na_active = function () { return na_active_row(); };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        document.getElementById('na-clouds-reload-all').addEventListener('click', function () {
            var rows = (na_clouds && na_clouds.list) || [];
            if (rows.length === 1) {
                Bridge.na_call_after_paint('cloud_reload', { id: rows[0].id }, 'Reloading ' + rows[0].name, 'Checking the LAS file...');
                return;
            }
            Bridge.na_call_after_paint('cloud_reload_all', {}, 'Reloading point clouds', 'Checking the LAS files...');
        });
        document.getElementById('na-view-zoom').addEventListener('click', function () {
            Bridge.na_call('view_zoom_to_cloud', {});
        });
        na_sorter = DragReorder.na_attach(document.getElementById('na-cloud-list'), {
            canDrag: function () {
                return na_sortable((na_clouds && na_clouds.list) || []);
            },
            onReorder: function (ids) {
                na_clear_confirm();
                Bridge.na_call('cloud_reorder', { ids: ids });
            },
            onEnd: function (changed) {
                var waiting = na_list_waiting;
                na_list_waiting = false;
                // After a change Ruby pushes the new order; otherwise catch up now
                if (!changed && (waiting || na_confirm_id)) na_render_list();
            }
        });
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', CloudSet.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__CloudSet = CloudSet;
})();
