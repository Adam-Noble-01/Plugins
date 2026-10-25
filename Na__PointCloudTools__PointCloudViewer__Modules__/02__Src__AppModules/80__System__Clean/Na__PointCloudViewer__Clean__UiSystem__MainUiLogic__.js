// =============================================================================
// NA POINT CLOUD VIEWER - CLEAN - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__Clean__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__CleanTab
// PURPOSE    : Clean tab: the preview region, the three filters (on / off,
//              strength, Advanced Settings), the preview results with the
//              Original / Cleaned / Differences switch and the surface check,
//              Clean & Export LAS, and Crop and Cut (v0.11.0): the Keep and Cut
//              boxes captured from the clip box, their own Original / Result /
//              Differences switch, exact counts, and Remove Points & Export LAS.
//
// STATE: everything shown comes from state.clean (Ruby). The filter cards are
//   built once from state.clean.filters, then only their values change, so an
//   open Advanced section, a slider being dragged or a value being typed is
//   never disturbed by a state push. The box list is rebuilt on each push,
//   except while a box is being renamed (the typing is never disturbed).
//
// =============================================================================

(function () {
    'use strict';

    var CleanTab = {};
    var Shell  = window.Na__PointCloudViewer__Shell;
    var Bridge = window.Na__PointCloudViewer__Bridge;

    var NA_FILTERS = ['noise', 'refine', 'density'];
    var NA_KIND_LABELS = { 1: 'Wall', 2: 'Floor or ceiling', 3: 'Sloping surface' };
    var NA_LEGEND = [
        ['removed', 'Removed as noise'],
        ['moved', 'Moved (light: a little, dark: the most)'],
        ['candidate', 'Reflection scatter (marked, kept)'],
        ['doubling', 'Doubled surface (marked, not moved)'],
        ['thinned', 'Thinned by Reduce Density'],
        ['unchanged', 'Unchanged (faded)']
    ];

    var na_clean       = null;     // last state.clean
    var na_built       = false;    // filter cards exist
    var na_dragging    = {};       // filter -> true while its slider is held
    var na_shown       = {};       // input id -> text last shown

    var NA_CONFIRM_MS   = 3000;
    var na_box_renaming = null;    // { id, text } while a Cut box is being renamed
    var na_box_confirm  = null;    // box id (or 'all') waiting for a second Delete click
    var na_box_timer    = null;

    // -------------------------------------------------------------------------
    // REGION | Helpers
    // -------------------------------------------------------------------------

    function na_el(id) { return document.getElementById(id); }

    function na_pct(part, whole) {
        if (!whole) return '0 %';
        var value = 100 * part / whole;
        return (value > 0 && value < 0.1 ? '<0.1' : value.toFixed(value < 10 ? 1 : 0)) + ' %';
    }

    function na_mm(value, digits) {
        if (value === null || value === undefined || !isFinite(value)) return '';
        return Number(value).toFixed(digits === undefined ? 1 : digits) + ' mm';
    }

    function na_trim(value) {
        if (value === null || value === undefined || !isFinite(value)) return '';
        var text = Number(value).toFixed(3);
        return text.indexOf('.') >= 0 ? text.replace(/0+$/, '').replace(/\.$/, '') : text;
    }

    function na_fill(input, text) {
        na_shown[input.id] = text;
        if (document.activeElement !== input) input.value = text;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Filter Cards (built once)
    // -------------------------------------------------------------------------

    function na_build_filters(filters) {
        var host = na_el('na-clean-filters');
        host.innerHTML = '';
        NA_FILTERS.forEach(function (key) {
            var spec = filters[key];
            if (!spec) return;
            var card = Shell.na_el('section', 'na-card na-clean-filter');
            card.id = 'na-clean-filter-' + key;

            var header = Shell.na_el('div', 'na-card__header');
            header.appendChild(Shell.na_el('h3', 'na-card__title', spec.label));
            var toggle = Shell.na_el('label', 'na-toggle');
            var check = document.createElement('input');
            check.type = 'checkbox';
            check.id = 'na-clean-' + key + '-enabled';
            toggle.appendChild(check);
            toggle.appendChild(Shell.na_el('span', 'na-toggle__track'));
            toggle.appendChild(Shell.na_el('span', 'na-toggle__label', 'On'));
            header.appendChild(toggle);
            card.appendChild(header);

            card.appendChild(Shell.na_el('p', 'na-clean-filter__summary', spec.summary));

            var row = Shell.na_el('div', 'na-clean-strength');
            row.appendChild(Shell.na_el('span', 'na-clean-strength__end', spec.strengthLow));
            var slider = document.createElement('input');
            slider.type = 'range';
            slider.className = 'na-slider';
            slider.min = '0'; slider.max = '100'; slider.step = '1';
            slider.id = 'na-clean-' + key + '-strength';
            row.appendChild(slider);
            row.appendChild(Shell.na_el('span', 'na-clean-strength__end', spec.strengthHigh));
            var value = Shell.na_el('span', 'na-card__value na-clean-strength__value');
            value.id = 'na-clean-' + key + '-strength-value';
            row.appendChild(value);
            card.appendChild(row);

            var mapped = Shell.na_el('p', 'na-hint na-clean-filter__mapped');
            mapped.id = 'na-clean-' + key + '-mapped';
            card.appendChild(mapped);

            var details = document.createElement('details');
            details.className = 'na-clean-advanced';
            details.appendChild(Shell.na_el('summary', 'na-clean-advanced__summary', 'Advanced Settings'));
            var grid = Shell.na_el('div', 'na-clean-advanced__grid');
            (spec.advanced || []).forEach(function (item) {
                grid.appendChild(na_build_advanced_row(key, item));
            });
            details.appendChild(grid);
            details.appendChild(Shell.na_el('p', 'na-hint', 'A typed value replaces the one the strength slider sets; clear it to go back. Reset to Defaults clears them all.'));
            card.appendChild(details);
            host.appendChild(card);

            na_wire_filter(key, check, slider, value);
        });
        na_built = true;
    }

    function na_build_advanced_row(filter, item) {
        var row = Shell.na_el('div', 'na-clean-advanced__row');
        row.title = item.hint || '';
        var label = Shell.na_el('span', 'na-clean-advanced__label', item.label);
        row.appendChild(label);
        var id = 'na-clean-adv-' + filter + '-' + item.key;
        if (item.kind === 'toggle') {
            var wrap = Shell.na_el('label', 'na-clean-advanced__check');
            var check = document.createElement('input');
            check.type = 'checkbox';
            check.id = id;
            wrap.appendChild(check);
            row.appendChild(wrap);
            row.appendChild(Shell.na_el('span', 'na-clean-advanced__unit', ''));
            check.addEventListener('change', function () {
                var advanced = {};
                advanced[item.key] = check.checked ? 1 : 0;
                Bridge.na_call('clean_set_filter', { filter: filter, advanced: advanced });
            });
        } else {
            var input = document.createElement('input');
            input.type = 'text';
            input.className = 'naInput na-clean-advanced__input';
            input.id = id;
            input.spellcheck = false;
            row.appendChild(input);
            row.appendChild(Shell.na_el('span', 'na-clean-advanced__unit', item.unit || ''));
            input.addEventListener('keydown', function (event) {
                if (event.key === 'Enter')  { input.blur(); }
                if (event.key === 'Escape') { input.value = na_shown[id] || ''; input.blur(); }
            });
            input.addEventListener('change', function () {
                var text = String(input.value || '').trim();
                if (text === na_shown[id]) return;
                var advanced = {};
                advanced[item.key] = text;     // '' = back to the value the slider sets
                Bridge.na_call('clean_set_filter', { filter: filter, advanced: advanced });
            });
        }
        if (item.hint) row.appendChild(Shell.na_el('span', 'na-clean-advanced__hint', item.hint));
        return row;
    }

    function na_wire_filter(key, check, slider, value) {
        check.addEventListener('change', function () {
            Bridge.na_call('clean_set_filter', { filter: key, enabled: check.checked });
        });
        slider.addEventListener('input', function () {
            na_dragging[key] = true;
            value.textContent = slider.value;
        });
        slider.addEventListener('change', function () {
            na_dragging[key] = false;
            Bridge.na_call('clean_set_filter', { filter: key, strength: Number(slider.value) });
        });
    }

    function na_render_filters(filters) {
        if (!na_built) na_build_filters(filters);
        NA_FILTERS.forEach(function (key) {
            var spec = filters[key];
            if (!spec) return;
            var card = na_el('na-clean-filter-' + key);
            na_el('na-clean-' + key + '-enabled').checked = !!spec.enabled;
            card.classList.toggle('na-clean-filter--off', !spec.enabled);
            if (!na_dragging[key]) {
                na_el('na-clean-' + key + '-strength').value = String(Math.round(spec.strength));
                na_el('na-clean-' + key + '-strength-value').textContent = String(Math.round(spec.strength));
            }
            na_el('na-clean-' + key + '-mapped').textContent = spec.enabled ? spec.mapped : 'Off: this filter changes nothing.';
            (spec.advanced || []).forEach(function (item) {
                var input = na_el('na-clean-adv-' + key + '-' + item.key);
                if (!input) return;
                if (item.kind === 'toggle') {
                    input.checked = Number(item.value) > 0.5;
                } else {
                    na_fill(input, na_trim(item.value));
                    input.classList.toggle('na-clean-advanced__input--override', !!item.isOverride);
                }
            });
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Preview Region + Results
    // -------------------------------------------------------------------------

    function na_render_region(clean) {
        var region = clean.region || {};
        var preview = clean.preview || {};
        Shell.na_text('na-clean-region-size', region.clipOn ? region.sizeText : '');
        var status;
        var measured = preview.stats && preview.isCurrent ? preview.stats.corePoints : null;
        if (!clean.hasCloud) status = clean.cloudName ? clean.cloudName + ' is not loaded. Reload it on the View tab to clean it.' : 'Load a point cloud to clean it.';
        else if (!region.clipOn) status = 'Clipping is off, so there is no region to preview.';
        else if (measured !== null) status = 'The clip box holds ' + Shell.na_format_int(measured) + ' points.';
        else status = 'The clip box holds roughly ' + Shell.na_format_int(region.estimatePoints) + ' points (an estimate until the preview has run)' +
                      (region.isLarge ? '. That is a large preview: a smaller box previews faster.' : '.');
        Shell.na_text('na-clean-region-status', status);
        var note = na_el('na-clean-region-note');
        note.textContent = preview.note || '';
        note.classList.toggle('na-hidden', !preview.note);
        na_el('na-clean-preview-now').disabled = !clean.hasCloud || !region.clipOn || !!clean.busy;
    }

    function na_render_badge(clean) {
        var preview = clean.preview || {};
        var badge = na_el('na-clean-state-badge');
        var text = '', modifier = '';
        if (!clean.hasCloud) { text = 'No cloud'; }
        else if (preview.state === 'running') {
            text = 'Working' + (preview.elapsedMs ? ' ' + (preview.elapsedMs / 1000).toFixed(1) + ' s' : '');
            modifier = 'na-clean-badge--running';
        } else if (preview.state === 'failed') { text = 'Failed'; modifier = 'na-clean-badge--failed'; }
        else if (preview.hasResult && preview.isCurrent) { text = 'Up to date'; modifier = 'na-clean-badge--done'; }
        else if (preview.hasResult) { text = 'Out of date'; modifier = 'na-clean-badge--stale'; }
        else { text = 'No preview'; }
        badge.textContent = text;
        badge.className = 'na-clean-badge ' + modifier;
    }

    function na_render_display(clean) {
        var display = clean.display || 'cleaned';
        Array.prototype.forEach.call(document.querySelectorAll('#na-clean-display-switch .na-switch__option'), function (button) {
            button.classList.toggle('na-switch__option--active', button.getAttribute('data-na-value') === display);
        });
        var legend = na_el('na-clean-legend');
        legend.classList.toggle('na-hidden', display !== 'differences');
        if (!legend.childElementCount) {
            NA_LEGEND.forEach(function (pair) {
                var item = Shell.na_el('span', 'na-clean-legend__item');
                item.appendChild(Shell.na_el('span', 'na-clean-chip na-clean-chip--' + pair[0]));
                item.appendChild(document.createTextNode(pair[1]));
                legend.appendChild(item);
            });
        }
        var preview = clean.preview || {};
        var note = '';
        if (clean.boxesShown) note = 'The model shows the Crop and Cut result (at the bottom of this tab), so this preview waits. Press Cleaned or Differences to preview the filters.';
        else if (preview.state === 'failed' && preview.error) note = preview.error;
        else if (clean.hasCloud && preview.hasResult && preview.showing === 'original' && display !== 'original') note = 'The model shows the original points while this tab is not showing a preview.';
        else if (clean.hasCloud && !preview.hasResult && preview.state !== 'running') note = 'The preview appears here once the clip box is on.';
        Shell.na_text('na-clean-results-note', note);
    }

    function na_render_stats(clean) {
        var stats = (clean.preview || {}).stats;
        if (!stats) { Shell.na_stat_grid('na-clean-stats', []); return; }
        var core = stats.corePoints;
        var noise = stats.removedIsolated + stats.removedCluster + stats.removedBlowout;
        var rows = [
            ['Points in the box', Shell.na_format_int(core)],
            ['Removed as noise', Shell.na_format_int(noise) + ' (' + na_pct(noise, core) + ')' +
                (stats.removedBlowout ? '; ' + Shell.na_format_int(stats.removedBlowout) + ' reflection scatter' : '')]
        ];
        if (stats.candidates) rows.push(['Reflection scatter marked', Shell.na_format_int(stats.candidates) + ' (kept; turn on Remove reflection scatter to remove)']);
        rows.push(['Refined', Shell.na_format_int(stats.moved) + ' (' + na_pct(stats.moved, core) + ')' +
                   (stats.moved ? ', median move ' + na_mm(stats.moveMedianMm) + ', largest ' + na_mm(stats.moveMaxMm) : '')]);
        if (stats.removedDensity) {
            var density = (clean.filters && clean.filters.density) || {};
            rows.push(['Thinned', Shell.na_format_int(stats.removedDensity) + ' (' + na_pct(stats.removedDensity, core) + '). ' + (density.mapped || '')]);
        }
        rows.push(['Kept', Shell.na_format_int(stats.kept) + ' (' + na_pct(stats.kept, core) + ')']);
        if (stats.doubling) rows.push(['Doubled surfaces marked', Shell.na_format_int(stats.doubling) + ' points, sheets up to ' + na_mm(stats.doublingGapMm, 0) + ' apart (not moved)']);
        if (stats.heldAmbiguous) rows.push(['Left alone where surfaces meet', Shell.na_format_int(stats.heldAmbiguous)]);
        if (stats.sigmaMm) rows.push(['Measured scan noise', na_mm(stats.sigmaMm)]);
        rows.push(['Preview time', (stats.totalMs / 1000).toFixed(1) + ' s (' + Shell.na_format_int(stats.gatheredPoints) + ' points read, margin ' + Math.round(stats.haloMm) + ' mm)']);
        Shell.na_stat_grid('na-clean-stats', rows);
    }

    // Before / after scatter across the main surfaces, or why there is no figure.
    function na_render_section(clean) {
        var host = na_el('na-clean-section');
        host.innerHTML = '';
        var preview = clean.preview || {};
        var stats = preview.stats;
        if (!stats) return;
        host.appendChild(Shell.na_el('p', 'na-switch-field__label na-clean-section__title', 'Surface Check'));
        if (stats.surfaceCount < 0 || !stats.surfaces || !stats.surfaces.length) {
            var box = Shell.na_el('div', 'na-clean-unsuitable');
            box.appendChild(Shell.na_el('strong', null, 'Not suitable for a single figure. '));
            box.appendChild(document.createTextNode(preview.surfaceNoteText || 'The box does not hold one clear surface.'));
            host.appendChild(box);
            return;
        }
        stats.surfaces.forEach(function (surface) {
            var card = Shell.na_el('div', 'na-clean-surface');
            var title = (NA_KIND_LABELS[surface.kind] || 'Surface') + ', ' + na_pct(surface.share, 1) + ' of the box';
            card.appendChild(Shell.na_el('div', 'na-clean-surface__title', title));
            var bar = Shell.na_el('div', 'na-clean-surface__bars');
            var max = Math.max(surface.bandBeforeMm, surface.bandAfterMm, 1e-6);
            [['Before', surface.bandBeforeMm, 'before'], ['After', surface.bandAfterMm, 'after']].forEach(function (entry) {
                var line = Shell.na_el('div', 'na-clean-surface__bar-row');
                line.appendChild(Shell.na_el('span', 'na-clean-surface__bar-label', entry[0]));
                var track = Shell.na_el('span', 'na-clean-surface__bar-track');
                var fill = Shell.na_el('span', 'na-clean-surface__bar-fill na-clean-surface__bar-fill--' + entry[2]);
                fill.style.width = Math.max(2, 100 * entry[1] / max) + '%';
                track.appendChild(fill);
                line.appendChild(track);
                line.appendChild(Shell.na_el('span', 'na-clean-surface__bar-value', na_mm(entry[1])));
                bar.appendChild(line);
            });
            card.appendChild(bar);
            var shift = Math.abs(surface.shiftMm) < 0.05 ? 0 : Number(surface.shiftMm);
            var notes = ['Scatter across the surface (5th to 95th percentile of distances to its plane). ' +
                         'Its middle moved ' + (shift > 0 ? '+' : '') + shift.toFixed(1) + ' mm.'];
            if (surface.flags & 1) notes.push('Holds a step or a second parallel sheet, so the scatter includes it.');
            if (surface.flags & 2) notes.push('Part of it is mixed with other surfaces.');
            if (surface.flags & 4) notes.push('Marked as a possible doubled surface: those points were not moved.');
            card.appendChild(Shell.na_el('p', 'na-hint na-hint--top', notes.join(' ')));
            host.appendChild(card);
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Export Card
    // -------------------------------------------------------------------------

    function na_render_export(clean) {
        var blocker = clean.hasCloud ? clean.exportBlocker : 'Load a point cloud first.';
        var button = na_el('na-clean-export');
        button.disabled = !!blocker || !!clean.busy;
        button.title = clean.suggestedName ? 'Suggested name: ' + clean.suggestedName : '';
        var note = na_el('na-clean-export-blocker');
        note.textContent = blocker || '';
        note.classList.toggle('na-hidden', !blocker);

        var retry = clean.retryLoad;
        na_el('na-clean-retry').classList.toggle('na-hidden', !retry);
        if (retry) {
            Shell.na_text('na-clean-retry-text', retry.fileName + ' was written and checked but is not loaded yet. The model still uses the original.');
            na_el('na-clean-retry-load').disabled = !!clean.busy;
        }

        var last = clean.lastExport;
        na_el('na-clean-last').classList.toggle('na-hidden', !last);
        if (!last) return;
        Shell.na_text('na-clean-last-title', 'Last export: ' + last.fileName);
        var rows = [
            ['Points written', Shell.na_format_int(last.written) + ' of ' + Shell.na_format_int(last.sourcePoints)],
            ['Removed', Shell.na_format_int(last.removed) + ' (' + na_pct(last.removed, last.sourcePoints) + '): ' +
                Shell.na_format_int(last.removedIsolated + last.removedCluster) + ' noise, ' +
                Shell.na_format_int(last.removedBlowout) + ' reflection scatter, ' + Shell.na_format_int(last.removedDensity) + ' thinned'],
            ['Refined', Shell.na_format_int(last.moved)],
            ['File size', (last.bytes / 1048576).toFixed(1) + ' MB'],
            ['Time', last.seconds + ' s in ' + last.tiles + ' tile' + (last.tiles === 1 ? '' : 's') + ', peak ' + last.peakWorkMb + ' MB working memory']
        ];
        if (last.heldRange) rows.push(['Kept in place', Shell.na_format_int(last.heldRange) + ' (the file\'s coordinate range could not hold the move)']);
        if (last.doubling) rows.push(['Doubled surfaces marked', Shell.na_format_int(last.doubling) + ' points (not moved)']);
        Shell.na_stat_grid('na-clean-last-stats', rows);
        Shell.na_text('na-clean-last-notes', (last.notes || []).join('. ') + ((last.notes || []).length ? '.' : ''));
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Crop and Cut (state.clean.boxes)
    // -------------------------------------------------------------------------

    function na_box_summary(boxes) {
        var cuts = (boxes.cuts || []).length;
        var parts = [];
        if (boxes.keep) parts.push('Keep box');
        if (cuts) parts.push(cuts + ' Cut box' + (cuts === 1 ? '' : 'es'));
        return parts.join(', ');
    }

    function na_render_box_clip(boxes) {
        var clip = boxes.clip || {};
        var text;
        if (!boxes.inModel) text = 'Import a point cloud to use Crop and Cut.';
        else if (!clip.hasBox) text = 'No clip box yet. Press Edit Clip Box and drag its sides round the area.';
        else if (clip.editing) text = 'Clip box ' + clip.sizeText + ', being edited in the model: drag the square handles, or type a distance.';
        else if (clip.enabled) text = 'Clip box ' + clip.sizeText + ', on.';
        else text = 'Clip box ' + clip.sizeText + ', off. Turn Clip on, or press Edit Clip Box, to fit it.';
        var line = na_el('na-boxes-clip-text');
        line.textContent = text;
        line.classList.toggle('na-boxes-clip__text--on', !!(clip.enabled || clip.editing));
        var toggle = na_el('na-boxes-clip-enabled');
        toggle.checked = !!clip.enabled;
        toggle.disabled = !boxes.inModel || !(clip.hasBox || boxes.hasCloud);
        var edit = na_el('na-boxes-clip-edit');
        edit.textContent = clip.editing ? 'Finish Editing' : 'Edit Clip Box';
        edit.classList.toggle('na-boxes-clip__edit--active', !!clip.editing);
        edit.disabled = !boxes.inModel || !(clip.hasBox || boxes.hasCloud);
    }

    function na_box_action(label, className, handler) {
        var button = Shell.na_el('button', 'na-scene-action' + (className ? ' ' + className : ''), label);
        button.type = 'button';
        button.addEventListener('click', function (event) { event.stopPropagation(); handler(); });
        return button;
    }

    function na_box_ask_delete(id) {
        if (na_box_confirm === id) {
            na_box_clear_confirm();
            Bridge.na_call(id === 'all' ? 'boxes_delete_all' : 'boxes_delete', { id: id });
            return;
        }
        na_box_clear_confirm();
        na_box_confirm = id;
        na_box_timer = window.setTimeout(function () {
            na_box_clear_confirm();
            if (na_clean) na_render_boxes(na_clean);
        }, NA_CONFIRM_MS);
        if (na_clean) na_render_boxes(na_clean);
    }

    function na_box_clear_confirm() {
        if (na_box_timer) window.clearTimeout(na_box_timer);
        na_box_timer = null;
        na_box_confirm = null;
    }

    function na_box_finish_rename(save) {
        if (!na_box_renaming) return;
        var renaming = na_box_renaming;
        na_box_renaming = null;
        if (save && renaming.text.trim()) {
            Bridge.na_call('boxes_rename', { id: renaming.id, name: renaming.text.trim() });
        } else if (na_clean) {
            na_render_boxes(na_clean);
        }
    }

    function na_box_rename_row(box) {
        var row = Shell.na_el('div', 'na-scene na-scene--renaming');
        row.appendChild(Shell.na_el('span', 'na-box-chip na-box-chip--cut', 'CUT'));
        var input = Shell.na_el('input', 'naInput na-scene__rename');
        input.type = 'text';
        input.id = 'na-box-rename-input';
        input.maxLength = 60;
        input.value = na_box_renaming.text;
        input.addEventListener('input', function () { na_box_renaming.text = input.value; });
        input.addEventListener('keydown', function (event) {
            if (event.key === 'Enter')  { na_box_finish_rename(true); }
            if (event.key === 'Escape') { na_box_finish_rename(false); }
        });
        row.appendChild(input);
        var actions = Shell.na_el('div', 'na-scene__actions');
        actions.appendChild(na_box_action('Save', 'na-scene-action--primary', function () { na_box_finish_rename(true); }));
        actions.appendChild(na_box_action('Cancel', '', function () { na_box_finish_rename(false); }));
        row.appendChild(actions);
        window.setTimeout(function () {
            if (document.activeElement !== input) { input.focus(); input.select(); }
        }, 0);
        return row;
    }

    // kind: 'keep' or 'cut'. A click on the name puts the box into the clip box.
    function na_box_row(box, kind) {
        var row = Shell.na_el('div', 'na-scene na-boxes-row' + (box.isShowing ? ' na-scene--active' : ''));
        row.appendChild(Shell.na_el('span', 'na-box-chip na-box-chip--' + kind, kind === 'keep' ? 'KEEP' : 'CUT'));
        var name = Shell.na_el('button', 'na-scene__name', box.name);
        name.type = 'button';
        name.title = 'Put this box into the clip box, to see it and fit it with Edit Clip Box';
        name.addEventListener('click', function () { Bridge.na_call('boxes_show_in_clip', { id: box.id }); });
        row.appendChild(name);
        row.appendChild(Shell.na_el('span', 'na-scene__tag', box.isChanged ? 'box changed' : box.sizeText));
        var actions = Shell.na_el('div', 'na-scene__actions');
        if (box.isChanged) {
            var update = na_box_action('Update', 'na-scene-action--primary', function () {
                Bridge.na_call('boxes_update', { id: box.id });
            });
            update.title = 'Save the clip box as it is now into ' + box.name;
            actions.appendChild(update);
        }
        if (kind === 'cut') {
            actions.appendChild(na_box_action('Rename', '', function () {
                na_box_clear_confirm();
                na_box_renaming = { id: box.id, text: box.name };
                if (na_clean) na_render_boxes(na_clean);
            }));
        }
        var confirming = na_box_confirm === box.id;
        actions.appendChild(na_box_action(confirming ? 'Click again to delete' : 'Delete', 'na-scene-action--danger', function () {
            na_box_ask_delete(box.id);
        }));
        row.appendChild(actions);
        return row;
    }

    function na_render_box_list(boxes) {
        var list = na_el('na-boxes-list');
        var cuts = boxes.cuts || [];
        if (na_box_renaming && !cuts.some(function (cut) { return cut.id === na_box_renaming.id; })) na_box_renaming = null;
        // a name being typed is never interrupted by a state push
        if (na_box_renaming && na_el('na-box-rename-input')) return;
        list.innerHTML = '';
        if (boxes.keep) list.appendChild(na_box_row(boxes.keep, 'keep'));
        cuts.forEach(function (cut) {
            list.appendChild(na_box_renaming && na_box_renaming.id === cut.id ? na_box_rename_row(cut) : na_box_row(cut, 'cut'));
        });
        var count = (boxes.keep ? 1 : 0) + cuts.length;
        list.classList.toggle('na-hidden', count === 0);
        na_el('na-boxes-list-foot').classList.toggle('na-hidden', count < 2);
        na_el('na-boxes-delete-all').textContent = na_box_confirm === 'all' ? 'Click again to delete every box' : 'Delete All Boxes';
    }

    function na_box_view_note(boxes) {
        var view = boxes.view || 'result';
        var note;
        if (!boxes.hasCloud) return 'Load the cloud (View tab) to see the result and how many points the boxes remove.';
        if (view === 'original') note = 'The model shows the cloud as it is, with the boxes outlined: green keeps what is inside it, red removes what is inside it.';
        else if (view === 'differences') note = 'Red: the points the boxes remove. The rest is faded. Nothing is removed until you export.';
        else note = 'The model shows the cloud as it will be saved: the points the boxes remove are hidden. Nothing is removed until you export.';
        if (boxes.clip && boxes.clip.enabled) note += ' Clipping is on, so only the part inside the clip box is drawn: turn Clip off to see the whole result.';
        return note;
    }

    function na_render_box_results(boxes) {
        var count = (boxes.keep ? 1 : 0) + (boxes.cuts || []).length;
        na_el('na-boxes-results').classList.toggle('na-hidden', count === 0);
        if (!count) return;
        var view = boxes.view || 'result';
        Array.prototype.forEach.call(document.querySelectorAll('#na-boxes-view-switch .na-switch__option'), function (button) {
            button.classList.toggle('na-switch__option--active', button.getAttribute('data-na-value') === view);
            button.disabled = !boxes.hasCloud;
        });
        Shell.na_text('na-boxes-view-note', na_box_view_note(boxes));
        var counts = boxes.counts;
        if (!counts) { Shell.na_stat_grid('na-boxes-stats', []); return; }
        var removed = counts.points - counts.kept;
        var rows = [];
        if (boxes.keep) rows.push(['Outside the Keep box', Shell.na_format_int(counts.outside) + ' (' + na_pct(counts.outside, counts.points) + ')']);
        if ((boxes.cuts || []).length) rows.push(['Inside the Cut boxes', Shell.na_format_int(counts.inside) + ' (' + na_pct(counts.inside, counts.points) + ')']);
        rows.push(['Removed', Shell.na_format_int(removed) + ' of ' + Shell.na_format_int(counts.points) + ' (' + na_pct(removed, counts.points) + ')']);
        rows.push(['Kept', Shell.na_format_int(counts.kept) + ' (' + na_pct(counts.kept, counts.points) + ')']);
        Shell.na_stat_grid('na-boxes-stats', rows);
    }

    function na_render_box_export(boxes) {
        var count = (boxes.keep ? 1 : 0) + (boxes.cuts || []).length;
        var blocker = boxes.exportBlocker;
        var button = na_el('na-boxes-export');
        button.disabled = !!blocker || !!boxes.busy;
        button.title = boxes.suggestedName ? 'Suggested name: ' + boxes.suggestedName : '';
        var note = na_el('na-boxes-export-blocker');
        note.textContent = count ? (blocker || '') : '';
        note.classList.toggle('na-hidden', !(count && blocker));

        var retry = boxes.retryLoad;
        na_el('na-boxes-retry').classList.toggle('na-hidden', !retry);
        if (retry) {
            Shell.na_text('na-boxes-retry-text', retry.fileName + ' was written and checked but is not loaded yet. The model still uses the original.');
            na_el('na-boxes-retry-load').disabled = !!boxes.busy;
        }

        var last = boxes.lastExport;
        na_el('na-boxes-last').classList.toggle('na-hidden', !last);
        if (!last) return;
        Shell.na_text('na-boxes-last-title', 'Last export: ' + last.fileName);
        var parts = [];
        if (last.removedKeep) parts.push(Shell.na_format_int(last.removedKeep) + ' outside the Keep box');
        if (last.removedCut) parts.push(Shell.na_format_int(last.removedCut) + ' inside the Cut boxes');
        Shell.na_stat_grid('na-boxes-last-stats', [
            ['Points written', Shell.na_format_int(last.written) + ' of ' + Shell.na_format_int(last.sourcePoints)],
            ['Removed', Shell.na_format_int(last.removed) + ' (' + na_pct(last.removed, last.sourcePoints) + ')' + (parts.length ? ': ' + parts.join(', ') : '')],
            ['File size', (last.bytes / 1048576).toFixed(1) + ' MB'],
            ['Time', last.seconds + ' s']
        ]);
        Shell.na_text('na-boxes-last-notes', (last.notes || []).join('. ') + ((last.notes || []).length ? '.' : ''));
    }

    function na_render_boxes(clean) {
        var boxes = clean.boxes || {};
        var card = na_el('na-boxes-card');
        card.classList.toggle('na-hidden', !boxes.isAvailable);
        if (!boxes.isAvailable) return;
        Shell.na_text('na-boxes-summary', na_box_summary(boxes));
        na_render_box_clip(boxes);
        var blocked = !!boxes.captureBlocker || !!boxes.busy;
        var outside = na_el('na-boxes-remove-outside');
        var inside = na_el('na-boxes-remove-inside');
        var full = (boxes.cuts || []).length >= boxes.maxCuts;
        outside.disabled = blocked;
        inside.disabled = blocked || full;
        outside.title = boxes.keep ? 'The clip box replaces the Keep box: every point outside it is removed'
                                   : 'The clip box becomes the Keep box: every point outside it is removed';
        inside.title = full ? 'This cloud has the most Cut boxes it can have (' + boxes.maxCuts + ')'
                            : 'The clip box becomes a Cut box: every point inside it is removed';
        // The clip box line above the buttons already says what to do when they
        // cannot capture, so the reason shows as their tooltip only.
        if (boxes.captureBlocker) {
            outside.title = boxes.captureBlocker;
            if (!full) inside.title = boxes.captureBlocker;
        }
        na_render_box_list(boxes);
        na_render_box_results(boxes);
        na_render_box_export(boxes);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render From State
    // -------------------------------------------------------------------------

    CleanTab.na_render = function (state) {
        if (!state || !state.clean || !state.clean.isAvailable) return;
        na_clean = state.clean;
        if (na_clean.filters) na_render_filters(na_clean.filters);
        na_render_region(na_clean);
        na_render_badge(na_clean);
        na_render_display(na_clean);
        na_render_stats(na_clean);
        na_render_section(na_clean);
        na_render_export(na_clean);
        na_render_boxes(na_clean);
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire_boxes() {
        na_el('na-boxes-remove-outside').addEventListener('click', function () {
            Bridge.na_call('boxes_remove_outside', {});
        });
        na_el('na-boxes-remove-inside').addEventListener('click', function () {
            Bridge.na_call('boxes_remove_inside', {});
        });
        na_el('na-boxes-clip-enabled').addEventListener('change', function (event) {
            Bridge.na_call('clip_set_enabled', { enabled: event.target.checked });
        });
        na_el('na-boxes-clip-edit').addEventListener('click', function () {
            Bridge.na_call('clip_toggle_edit', {});
        });
        na_el('na-boxes-delete-all').addEventListener('click', function () {
            na_box_ask_delete('all');
        });
        Array.prototype.forEach.call(document.querySelectorAll('#na-boxes-view-switch .na-switch__option'), function (button) {
            button.addEventListener('click', function () {
                Bridge.na_call('boxes_set_view', { view: button.getAttribute('data-na-value') });
            });
        });
        // Save As is modal; the export reports progress itself once it starts.
        na_el('na-boxes-export').addEventListener('click', function () {
            Bridge.na_call('boxes_export', {});
        });
        na_el('na-boxes-retry-load').addEventListener('click', function () {
            Bridge.na_call('clean_retry_load', {});
        });
    }

    function na_wire() {
        Array.prototype.forEach.call(document.querySelectorAll('#na-clean-display-switch .na-switch__option'), function (button) {
            button.addEventListener('click', function () {
                Bridge.na_call('clean_set_display', { display: button.getAttribute('data-na-value') });
            });
        });
        na_el('na-clean-go-clipping').addEventListener('click', function () {
            if (window.Na_TabRouter) window.Na_TabRouter.na_activateTab('clipping');
        });
        na_el('na-clean-preview-now').addEventListener('click', function () {
            Bridge.na_call('clean_preview_now', {});
        });
        na_el('na-clean-reset').addEventListener('click', function () {
            Bridge.na_call('clean_reset_defaults', {});
        });
        // Save As is modal; the export reports progress itself once it starts.
        na_el('na-clean-export').addEventListener('click', function () {
            Bridge.na_call('clean_export', {});
        });
        na_el('na-clean-retry-load').addEventListener('click', function () {
            Bridge.na_call('clean_retry_load', {});
        });
        na_wire_boxes();
        if (window.Na_TabRouter) {
            window.Na_TabRouter.na_on_change(function (tabId) {
                Bridge.na_call('clean_tab_active', { active: tabId === 'clean' });
            });
        }
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', CleanTab.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        window.setTimeout(na_wire, 0);
    }

    window.Na__PointCloudViewer__CleanTab = CleanTab;
})();
