// =============================================================================
// NA POINT CLOUD VIEWER - CLEAN - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__Clean__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__CleanTab
// PURPOSE    : Clean tab: the preview region, the three filters (on / off,
//              strength, Advanced Settings), the preview results with the
//              Original / Cleaned / Differences switch and the surface check,
//              and Clean & Export LAS.
//
// STATE: everything shown comes from state.clean (Ruby). The filter cards are
//   built once from state.clean.filters, then only their values change, so an
//   open Advanced section, a slider being dragged or a value being typed is
//   never disturbed by a state push.
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
        if (!clean.hasCloud) status = 'Load a point cloud to clean it.';
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
        if (preview.state === 'failed' && preview.error) note = preview.error;
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
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

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
