// =============================================================================
// NA POINT CLOUD VIEWER - TRANSFORM - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__Transform__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__TransformTab
// PURPOSE    : Transform tab: lock / unlock, the Move and Rotate tools, the
//              gimbal point, typed position and rotation, snapping preferences
//              and the configuration export.
//
// STATE: everything shown comes from state.transform (Ruby). This file only
//   remembers what the user is typing, so a state push (for example while
//   the cloud is being dragged in the model) never wipes a half-typed value.
//
// =============================================================================

(function () {
    'use strict';

    var TransformTab = {};
    var Shell  = window.Na__PointCloudViewer__Shell;
    var Bridge = window.Na__PointCloudViewer__Bridge;

    var NA_VALUE_KEYS = ['x', 'y', 'z', 'rotZ', 'rotX', 'rotY'];
    var NA_CONFIRM_MS = 3000;
    var NA_TOOL_HINTS = {
        none:   'Move shows a gimbal at the gimbal point. Rotate works like SketchUp\'s Rotate tool.',
        move:   'Drag a red, green or blue arrow on the gimbal, or click an arrow, move and click. Type a distance for precision. Esc cancels a move. Set Gimbal Point puts the gimbal on any point you click.',
        pick:   'Click a point in the model for the gimbal. It snaps to vertices, edges and other points. Esc keeps the current gimbal point.',
        rotate: 'Click the centre, then a starting direction, then move and click to finish. Click on a model edge or point to line the cloud up with it. Arrow keys lock the axis. Type an angle for precision.'
    };

    var na_xform        = null;   // last state.transform
    var na_shown        = {};     // input id -> text last shown (unchanged text is not re-sent)
    var na_reset_armed  = false;
    var na_reset_timer  = null;

    // -------------------------------------------------------------------------
    // REGION | Helpers
    // -------------------------------------------------------------------------

    function na_el(id) { return document.getElementById(id); }

    // Never overwrite the field the user is typing in.
    function na_fill(id, text) {
        var input = na_el(id);
        na_shown[id] = text;
        if (document.activeElement !== input) input.value = text;
    }

    function na_wire_text(id, send) {
        var input = na_el(id);
        input.addEventListener('keydown', function (event) {
            if (event.key === 'Enter')  { input.blur(); }
            if (event.key === 'Escape') { input.value = na_shown[id] || ''; input.blur(); }
        });
        input.addEventListener('change', function () {
            var value = String(input.value || '').trim();
            if (!value || value === na_shown[id]) return;
            send(value);
        });
    }

    function na_disarm_reset() {
        if (na_reset_timer) window.clearTimeout(na_reset_timer);
        na_reset_timer = null;
        na_reset_armed = false;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render From State
    // -------------------------------------------------------------------------

    function na_render_position_card(xf) {
        var hasCloud = !!xf.hasCloud;
        var locked   = !hasCloud || !!xf.locked;

        var badge = na_el('na-xform-badge');
        badge.textContent = !hasCloud ? 'No cloud' : (locked ? 'Locked' : 'Unlocked');
        badge.className = 'na-lock-badge' + (hasCloud && !locked ? ' na-lock-badge--open' : '');

        Shell.na_text('na-xform-status', !hasCloud
            ? 'Import a point cloud to position it.'
            : (locked ? 'Position locked. The cloud cannot be moved or rotated until you unlock it.'
                      : 'Unlocked. Move or rotate the cloud, or type values below, then lock it again.'));

        var note = na_el('na-xform-note');
        note.textContent = xf.note || '';
        note.classList.toggle('na-hidden', !xf.note);

        var lock = na_el('na-xform-lock');
        lock.textContent = locked ? 'Unlock to Transform' : 'Lock Position';
        lock.disabled = !hasCloud;

        [['move', 'na-xform-move'], ['rotate', 'na-xform-rotate']].forEach(function (pair) {
            var button = na_el(pair[1]);
            var active = xf.activeTool === pair[0];
            button.disabled = locked;
            button.classList.toggle('na-tool-button--active', active);
            button.textContent = pair[0] === 'move' ? (active ? 'Finish Moving' : 'Move') : (active ? 'Finish Rotating' : 'Rotate');
        });
        var hint = na_el('na-xform-tool-hint');
        hint.textContent = NA_TOOL_HINTS[xf.pickingGimbal ? 'pick' : (xf.activeTool || 'none')];
        hint.classList.toggle('na-hint--live', !!xf.activeTool);

        var pick = na_el('na-xform-pick-gimbal');
        pick.disabled = locked;
        pick.classList.toggle('na-tool-button--active', !!xf.pickingGimbal);
        pick.textContent = xf.pickingGimbal ? 'Click a Point in the Model' : 'Set Gimbal Point';
        na_el('na-xform-centre-gimbal').disabled = locked || !xf.gimbalIsCustom;
    }

    function na_render_values(xf) {
        var hasCloud = !!xf.hasCloud;
        var editable = hasCloud && !xf.locked;
        Shell.na_text('na-xform-caption', hasCloud
            ? 'The gimbal point (' + (xf.gimbalIsCustom ? 'a point you picked' : 'centre of the cloud\'s box') + '; survey ' + xf.gimbalSurvey + ') sits at:'
            : 'The gimbal point sits at:');
        var values = {
            x: hasCloud ? xf.position.x : '', y: hasCloud ? xf.position.y : '', z: hasCloud ? xf.position.z : '',
            rotZ: hasCloud ? xf.rotation.z : '', rotX: hasCloud ? xf.rotation.x : '', rotY: hasCloud ? xf.rotation.y : ''
        };
        NA_VALUE_KEYS.forEach(function (key) {
            na_fill('na-xform-' + key, values[key]);
            na_el('na-xform-' + key).disabled = !editable;
        });
        Array.prototype.forEach.call(document.querySelectorAll('#na-tab-transform [data-na-unit]'), function (span) {
            span.textContent = span.getAttribute('data-na-unit') === 'angle' ? '°' : (xf.unit || '');
        });

        var reset = na_el('na-xform-reset');
        if (!editable || xf.isImportPosition) na_disarm_reset();
        reset.disabled = !editable || !!xf.isImportPosition;
        reset.textContent = na_reset_armed ? 'Click again to reset' : 'Reset to Import Position';
        reset.classList.toggle('na-button--danger', na_reset_armed);
    }

    function na_render_snap(xf) {
        var snap = xf.snap || {};
        na_el('na-snap-move').checked  = !!snap.moveEnabled;
        na_el('na-snap-angle').checked = !!snap.angleEnabled;
        na_fill('na-snap-move-step', snap.moveText || '');
        na_fill('na-snap-angle-step', snap.angleText || '');
    }

    TransformTab.na_render = function (state) {
        if (!state || !state.transform || !state.transform.isAvailable) return;
        na_xform = state.transform;
        na_render_position_card(na_xform);
        na_render_values(na_xform);
        na_render_snap(na_xform);
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        na_el('na-xform-lock').addEventListener('click', function () {
            if (!na_xform || !na_xform.hasCloud) return;
            Bridge.na_call('transform_set_locked', { locked: !na_xform.locked });
        });
        na_el('na-xform-move').addEventListener('click', function () {
            Bridge.na_call('transform_toggle_tool', { tool: 'move' });
        });
        na_el('na-xform-rotate').addEventListener('click', function () {
            Bridge.na_call('transform_toggle_tool', { tool: 'rotate' });
        });
        na_el('na-xform-pick-gimbal').addEventListener('click', function () {
            Bridge.na_call('transform_pick_gimbal', {});
        });
        na_el('na-xform-centre-gimbal').addEventListener('click', function () {
            Bridge.na_call('transform_centre_gimbal', {});
        });

        NA_VALUE_KEYS.forEach(function (key) {
            na_wire_text('na-xform-' + key, function (value) {
                var values = {};
                values[key] = value;
                Bridge.na_call('transform_set_values', { values: values });
            });
        });

        na_el('na-xform-reset').addEventListener('click', function () {
            if (!na_reset_armed) {
                na_reset_armed = true;
                na_reset_timer = window.setTimeout(function () {
                    na_disarm_reset();
                    if (na_xform) na_render_values(na_xform);
                }, NA_CONFIRM_MS);
                if (na_xform) na_render_values(na_xform);
                return;
            }
            na_disarm_reset();
            Bridge.na_call('transform_reset', {});
        });

        na_el('na-snap-move').addEventListener('change', function (event) {
            Bridge.na_call('transform_set_snap', { moveEnabled: event.target.checked });
        });
        na_el('na-snap-angle').addEventListener('change', function (event) {
            Bridge.na_call('transform_set_snap', { angleEnabled: event.target.checked });
        });
        na_wire_text('na-snap-move-step', function (value) {
            Bridge.na_call('transform_set_snap', { moveText: value });
        });
        na_wire_text('na-snap-angle-step', function (value) {
            Bridge.na_call('transform_set_snap', { angleText: value });
        });

        na_el('na-xform-export').addEventListener('click', function () {
            Bridge.na_call('config_export', {});
        });
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', TransformTab.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__TransformTab = TransformTab;
})();
