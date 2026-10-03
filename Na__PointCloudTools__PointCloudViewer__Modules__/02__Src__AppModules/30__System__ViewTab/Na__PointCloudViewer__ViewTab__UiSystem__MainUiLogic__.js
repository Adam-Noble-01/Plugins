// =============================================================================
// NA POINT CLOUD VIEWER - VIEW TAB - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__ViewTab__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__ViewTab
// PURPOSE    : The loaded cloud, Point Budget, Point Size, Point Opacity,
//              Colour Mode, the Show switch and the units summary.
//
// INTERACTION:
//   Size and opacity stream while dragging (trailing throttle). Point Budget
//   is applied on release. A control being dragged is never overwritten by an
//   incoming state push.
//
// =============================================================================

(function () {
    'use strict';

    var ViewTab = {};
    var Shell   = window.Na__PointCloudViewer__Shell;
    var Bridge  = window.Na__PointCloudViewer__Bridge;

    var NA_SLIDER_STEPS   = 1000;
    var NA_STREAM_DELAY   = 90;
    var na_dragging       = {};
    var na_timers         = {};
    var na_budget_range   = { min: 10000, max: 20000000 };

    // -------------------------------------------------------------------------
    // REGION | Settings Out
    // -------------------------------------------------------------------------

    function na_send(partial) {
        Bridge.na_call('render_update_settings', partial);
    }

    // Trailing throttle: the value is read when the timer fires, so the last
    // position of a drag is always the one that lands.
    function na_stream(key, readPartial) {
        if (na_timers[key]) return;
        na_timers[key] = window.setTimeout(function () {
            na_timers[key] = null;
            na_send(readPartial());
        }, NA_STREAM_DELAY);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Point Budget (logarithmic slider)
    // -------------------------------------------------------------------------

    function na_round_nice(value) {
        if (value <= 0) return 0;
        var magnitude = Math.pow(10, Math.max(0, Math.floor(Math.log10(value)) - 2));
        return Math.round(value / magnitude) * magnitude;
    }

    function na_budget_from_slider(position) {
        var min = na_budget_range.min, max = na_budget_range.max;
        if (max <= min) return max;
        var raw = min * Math.pow(max / min, position / NA_SLIDER_STEPS);
        return Math.min(max, Math.max(min, na_round_nice(raw)));
    }

    function na_slider_from_budget(budget) {
        var min = na_budget_range.min, max = na_budget_range.max;
        if (max <= min) return NA_SLIDER_STEPS;
        var clamped = Math.min(max, Math.max(min, budget));
        return Math.round(Math.log(clamped / min) / Math.log(max / min) * NA_SLIDER_STEPS);
    }

    // With a cloud loaded, presets at or above its size are replaced by one
    // "All" preset: a budget above the cloud's own point count draws nothing
    // more, so the cloud's size IS the top of the scale.
    function na_render_presets(presets, activeBudget, totalPoints) {
        var row = document.getElementById('na-view-budget-presets');
        row.innerHTML = '';
        var shown = presets.filter(function (preset) { return !totalPoints || preset.points < totalPoints; });
        if (totalPoints) shown.push({ label: 'All', points: totalPoints, isAll: true });
        shown.forEach(function (preset) {
            var button = Shell.na_el('button', 'na-preset', preset.label);
            button.type = 'button';
            button.title = Shell.na_format_int(preset.points) + ' points' + (preset.isAll ? ' (every point in the cloud)' : '');
            var active = preset.isAll ? activeBudget >= totalPoints : preset.points === activeBudget;
            if (active) button.classList.add('na-preset--active');
            button.addEventListener('click', function () { na_send({ pointBudget: preset.points }); });
            row.appendChild(button);
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render From State
    // -------------------------------------------------------------------------

    function na_render_cloud(state) {
        var summary = document.getElementById('na-view-cloud-summary');
        var cloud   = state.cloud || {};
        summary.classList.toggle('na-cloud-summary--empty', !cloud.isLoaded);
        summary.innerHTML = '';
        if (cloud.isLoaded) {
            summary.appendChild(Shell.na_el('div', 'na-cloud-summary__name', cloud.label));
            summary.appendChild(Shell.na_el('div', 'na-cloud-summary__detail',
                Shell.na_format_int(cloud.totalPoints) + ' points, ' + cloud.sizeText + ', source in ' + String(cloud.sourceUnit || '').toLowerCase()));
        } else {
            summary.textContent = 'No point cloud loaded. Press Import LAS to choose a file.';
        }
        document.getElementById('na-view-visible').checked = !!(state.overlay && state.overlay.isVisible);
        document.getElementById('na-view-zoom').disabled   = !cloud.isLoaded;
        document.getElementById('na-view-unload').disabled = !cloud.isLoaded;

        var fault = document.getElementById('na-view-fault');
        var message = state.render && state.render.fault;
        fault.textContent = message ? 'Drawing stopped after an error: ' + message + '. Change any setting to try again.' : '';
        fault.classList.toggle('na-hidden', !message);
    }

    function na_render_budget(state) {
        var render   = state.render;
        var settings = render.settings;
        var limits   = render.limits;
        var cloud    = state.cloud || {};
        var cap      = cloud.isLoaded ? Math.min(limits.pointBudgetMax, cloud.totalPoints) : limits.pointBudgetMax;

        na_budget_range = { min: Math.min(limits.pointBudgetMin, cap), max: cap };
        var showsAll = cloud.isLoaded && settings.pointBudget >= cloud.totalPoints;
        Shell.na_text('na-view-budget-value', (showsAll ? 'All ' : '') + Shell.na_format_int(Math.min(settings.pointBudget, cap)));
        if (!na_dragging.budget) {
            document.getElementById('na-view-budget-slider').value = na_slider_from_budget(settings.pointBudget);
            if (document.activeElement !== document.getElementById('na-view-budget-input')) {
                document.getElementById('na-view-budget-input').value = settings.pointBudget;
            }
        }
        na_render_presets(render.budgetPresets || [], settings.pointBudget, cloud.isLoaded ? cloud.totalPoints : 0);

        Shell.na_text('na-view-budget-hint', cloud.isLoaded
            ? (showsAll
                ? 'Every point in the cloud is drawn (' + Shell.na_format_int(cloud.totalPoints) + '). This is the top of the scale for this cloud.'
                : 'Up to ' + Shell.na_format_int(settings.pointBudget) + ' of ' + Shell.na_format_int(cloud.totalPoints) +
                  ' points are drawn, spread evenly over the cloud. With clipping on, the budget counts points inside the clip box.')
            : 'The most points drawn at once. The top of the scale is the loaded cloud\'s own point count (up to ' +
              Shell.na_format_int(limits.pointBudgetMax) + ').');
    }

    function na_render_appearance(settings, limits) {
        var size    = document.getElementById('na-view-size-slider');
        var opacity = document.getElementById('na-view-opacity-slider');
        size.min = limits.pointSizeMinPx;  size.max = limits.pointSizeMaxPx;
        opacity.min = limits.opacityMinPct; opacity.max = limits.opacityMaxPct;
        if (!na_dragging.size)    size.value    = settings.pointSizePx;
        if (!na_dragging.opacity) opacity.value = settings.opacityPercent;
        Shell.na_text('na-view-size-value', settings.pointSizePx + ' px');
        Shell.na_text('na-view-opacity-value', settings.opacityPercent + '%');

        var options = document.querySelectorAll('#na-view-colour-switch .na-switch__option');
        Array.prototype.forEach.call(options, function (option) {
            option.classList.toggle('na-switch__option--active', option.getAttribute('data-na-value') === settings.colourMode);
        });
    }

    function na_render_units(units) {
        Shell.na_text('na-units-model',    units.modelUnits);
        Shell.na_text('na-units-source',   units.sourceUnits);
        Shell.na_text('na-units-internal', units.internalStorage);
    }

    ViewTab.na_render = function (state) {
        if (!state || !state.render) return;
        na_render_cloud(state);
        na_render_budget(state);
        na_render_appearance(state.render.settings, state.render.limits);
        na_render_units(state.units || {});
        Shell.na_text('na-brand-version', state.plugin ? 'v' + state.plugin.version + ' by Noble Architecture' : 'by Noble Architecture');
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_track_drag(element, key) {
        element.addEventListener('pointerdown', function () { na_dragging[key] = true; });
        element.addEventListener('pointerup',   function () { na_dragging[key] = false; });
        element.addEventListener('blur',        function () { na_dragging[key] = false; });
    }

    function na_wire() {
        var budgetSlider = document.getElementById('na-view-budget-slider');
        var budgetInput  = document.getElementById('na-view-budget-input');
        var sizeSlider   = document.getElementById('na-view-size-slider');
        var opacity      = document.getElementById('na-view-opacity-slider');

        na_track_drag(budgetSlider, 'budget');
        budgetSlider.addEventListener('input', function () {
            Shell.na_text('na-view-budget-value', Shell.na_format_int(na_budget_from_slider(Number(budgetSlider.value))));
        });
        budgetSlider.addEventListener('change', function () {
            na_dragging.budget = false;
            na_send({ pointBudget: na_budget_from_slider(Number(budgetSlider.value)) });
        });
        budgetInput.addEventListener('change', function () {
            var value = Math.round(Number(budgetInput.value));
            if (isFinite(value) && value > 0) na_send({ pointBudget: value });
        });

        na_track_drag(sizeSlider, 'size');
        sizeSlider.addEventListener('input', function () {
            Shell.na_text('na-view-size-value', sizeSlider.value + ' px');
            na_stream('size', function () { return { pointSizePx: Number(sizeSlider.value) }; });
        });

        na_track_drag(opacity, 'opacity');
        opacity.addEventListener('input', function () {
            Shell.na_text('na-view-opacity-value', opacity.value + '%');
            na_stream('opacity', function () { return { opacityPercent: Number(opacity.value) }; });
        });

        var colourOptions = document.querySelectorAll('#na-view-colour-switch .na-switch__option');
        Array.prototype.forEach.call(colourOptions, function (option) {
            option.addEventListener('click', function () { na_send({ colourMode: option.getAttribute('data-na-value') }); });
        });

        document.getElementById('na-view-visible').addEventListener('change', function (event) {
            Bridge.na_call('render_set_visible', { isVisible: event.target.checked });
        });
        document.getElementById('na-view-zoom').addEventListener('click', function () {
            Bridge.na_call('view_zoom_to_cloud', {});
        });
        document.getElementById('na-view-unload').addEventListener('click', function () {
            Bridge.na_call('cloud_unload', {});
        });
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', ViewTab.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__ViewTab = ViewTab;
})();
