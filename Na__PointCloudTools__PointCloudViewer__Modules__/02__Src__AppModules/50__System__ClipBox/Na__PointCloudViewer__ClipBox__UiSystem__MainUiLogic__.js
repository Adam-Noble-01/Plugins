// =============================================================================
// NA POINT CLOUD VIEWER - CLIP BOX - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__ClipBox__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__ClipBox
// PURPOSE    : Clipping tab: the Clip switch, Edit Clip Box, Reset to Cloud,
//              the six typed limits and the saved clip scenes.
//
// STATE: everything shown comes from state.clip (Ruby). This file never keeps
//   its own copy of the box; it only remembers what the user is typing, so a
//   state push never wipes a half-typed limit or scene name.
//
// =============================================================================

(function () {
    'use strict';

    var ClipBox = {};
    var Shell   = window.Na__PointCloudViewer__Shell;
    var Bridge  = window.Na__PointCloudViewer__Bridge;

    var NA_PAIRS = [['left', 'right'], ['front', 'back'], ['bottom', 'top']];
    var NA_CONFIRM_MS = 3000;
    var NA_HINT_IDLE    = 'Edit Clip Box shows the box in the model so you can move its sides with the mouse.';
    var NA_HINT_EDITING = 'Drag a square handle to move that side, or click it, move and click. Type a distance and press Enter for precision. Esc cancels a move. Finish Editing, or any other tool, ends editing.';

    var na_clip          = null;     // last state.clip
    var na_shown_limits  = {};       // faceId -> text last shown (unchanged text is not re-sent)
    var na_renaming      = null;     // { id, text } while a scene name is being edited
    var na_confirm_id    = null;     // scene waiting for a second Delete click
    var na_confirm_timer = null;

    // -------------------------------------------------------------------------
    // REGION | Clip Box Card
    // -------------------------------------------------------------------------

    function na_status_text(clip) {
        if (!clip.isAvailable) return 'Clipping is not available for this model.';
        if (!clip.hasBox && !clip.hasCloud) return 'Import a point cloud to use the clip box.';
        if (!clip.hasBox) return 'Clipping is off. Turn Clip on, or press Edit Clip Box, to start from the cloud\'s bounds.';
        var text = clip.enabled ? 'Clipping is on. Points outside the box are hidden.' : 'Clipping is off. The whole cloud is shown.';
        if (!clip.hasCloud) text += ' No cloud is loaded in this session; the box is kept with the model.';
        if (clip.isEditing) text += ' The box is shown in the model for editing.';
        return text;
    }

    function na_render_box(clip) {
        var usable = clip.isAvailable && (clip.hasBox || clip.hasCloud);
        var toggle = document.getElementById('na-clip-enabled');
        toggle.checked  = !!clip.enabled;
        toggle.disabled = !usable;

        var status = document.getElementById('na-clip-status');
        status.textContent = na_status_text(clip);
        status.classList.toggle('na-clip-status--on', !!clip.enabled);

        var edit = document.getElementById('na-clip-edit');
        edit.textContent = clip.isEditing ? 'Finish Editing' : 'Edit Clip Box';
        edit.classList.toggle('naButton--active', !!clip.isEditing);
        edit.disabled = !usable;
        document.getElementById('na-clip-reset').disabled = !clip.hasCloud;
        var hint = document.getElementById('na-clip-edit-hint');
        hint.textContent = clip.isEditing ? NA_HINT_EDITING : NA_HINT_IDLE;
        hint.classList.toggle('na-hint--live', !!clip.isEditing);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Typed Limits
    // -------------------------------------------------------------------------

    function na_limit_input(faceId) {
        return document.getElementById('na-clip-limit-' + faceId);
    }

    function na_build_limits(limits) {
        var wrap = document.getElementById('na-clip-limits');
        if (wrap.childNodes.length) return;
        var labels = {};
        limits.forEach(function (limit) { labels[limit.id] = limit.label; });
        NA_PAIRS.forEach(function (pair) {
            pair.forEach(function (faceId) {
                var field = Shell.na_el('label', 'na-clip-field');
                field.appendChild(Shell.na_el('span', 'na-clip-field__label', labels[faceId] || faceId));
                var input = Shell.na_el('input', 'naInput na-clip-field__input');
                input.type = 'text';
                input.id = 'na-clip-limit-' + faceId;
                input.setAttribute('data-na-face', faceId);
                input.spellcheck = false;
                input.addEventListener('keydown', function (event) {
                    if (event.key === 'Enter')  { input.blur(); }
                    if (event.key === 'Escape') { input.value = na_shown_limits[faceId] || ''; input.blur(); }
                });
                input.addEventListener('change', function () { na_send_limit(faceId, input.value); });
                field.appendChild(input);
                field.appendChild(Shell.na_el('span', 'na-clip-field__unit', ''));
                wrap.appendChild(field);
            });
        });
    }

    function na_render_limits(clip) {
        na_build_limits(clip.limits || []);
        (clip.limits || []).forEach(function (limit) {
            var input = na_limit_input(limit.id);
            if (!input) return;
            input.disabled = !clip.hasBox;
            input.parentNode.querySelector('.na-clip-field__unit').textContent = clip.unit || '';
            na_shown_limits[limit.id] = limit.value;
            if (document.activeElement !== input) input.value = limit.value;
        });
    }

    function na_send_limit(faceId, text) {
        var value = String(text || '').trim();
        if (!value || value === na_shown_limits[faceId]) return;
        var limits = {};
        limits[faceId] = value;
        Bridge.na_call('clip_set_limits', { limits: limits });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Clip Scenes
    // -------------------------------------------------------------------------

    function na_action_button(label, className, handler) {
        var button = Shell.na_el('button', 'na-scene-action' + (className ? ' ' + className : ''), label);
        button.type = 'button';
        button.addEventListener('click', function (event) { event.stopPropagation(); handler(); });
        return button;
    }

    function na_scene_row(options) {
        var row = Shell.na_el('div', 'na-scene' + (options.isActive ? ' na-scene--active' : ''));
        var name = Shell.na_el('button', 'na-scene__name', options.name);
        name.type = 'button';
        name.title = options.isActive ? 'Showing now' : 'Switch to ' + options.name;
        name.addEventListener('click', function () { Bridge.na_call('clip_scene_activate', { id: options.id }); });
        row.appendChild(name);
        if (options.tag) row.appendChild(Shell.na_el('span', 'na-scene__tag', options.tag));
        return row;
    }

    function na_rename_row(scene) {
        var row = Shell.na_el('div', 'na-scene na-scene--renaming');
        var input = Shell.na_el('input', 'naInput na-scene__rename');
        input.type = 'text';
        input.maxLength = 60;
        input.value = na_renaming.text;
        input.addEventListener('input', function () { na_renaming.text = input.value; });
        input.addEventListener('keydown', function (event) {
            if (event.key === 'Enter')  { na_finish_rename(true); }
            if (event.key === 'Escape') { na_finish_rename(false); }
        });
        row.appendChild(input);
        var actions = Shell.na_el('div', 'na-scene__actions');
        actions.appendChild(na_action_button('Save', 'na-scene-action--primary', function () { na_finish_rename(true); }));
        actions.appendChild(na_action_button('Cancel', '', function () { na_finish_rename(false); }));
        row.appendChild(actions);
        window.setTimeout(function () {
            if (document.activeElement !== input) { input.focus(); input.select(); }
        }, 0);
        return row;
    }

    function na_finish_rename(save) {
        if (!na_renaming) return;
        var renaming = na_renaming;
        na_renaming = null;
        if (save && renaming.text.trim()) {
            Bridge.na_call('clip_scene_rename', { id: renaming.id, name: renaming.text.trim() });
        } else if (na_clip) {
            na_render_scenes(na_clip);
        }
    }

    function na_ask_delete(scene) {
        if (na_confirm_id === scene.id) {
            na_clear_confirm();
            Bridge.na_call('clip_scene_delete', { id: scene.id });
            return;
        }
        na_clear_confirm();
        na_confirm_id = scene.id;
        na_confirm_timer = window.setTimeout(function () {
            na_clear_confirm();
            if (na_clip) na_render_scenes(na_clip);
        }, NA_CONFIRM_MS);
        na_render_scenes(na_clip);
    }

    function na_clear_confirm() {
        if (na_confirm_timer) window.clearTimeout(na_confirm_timer);
        na_confirm_timer = null;
        na_confirm_id = null;
    }

    function na_render_scenes(clip) {
        var list = document.getElementById('na-scene-list');
        list.innerHTML = '';

        list.appendChild(na_scene_row({
            id: 'full', name: 'Full Cloud', isActive: !!clip.fullCloudActive,
            tag: clip.fullCloudActive ? 'showing' : ''
        }));

        (clip.scenes || []).forEach(function (scene) {
            if (na_renaming && na_renaming.id === scene.id) {
                list.appendChild(na_rename_row(scene));
                return;
            }
            var tag = scene.isModified ? 'box changed' : (scene.isActive ? 'showing' : '');
            var row = na_scene_row({ id: scene.id, name: scene.name, isActive: scene.isActive, tag: tag });
            var actions = Shell.na_el('div', 'na-scene__actions');
            if (scene.isModified) {
                var update = na_action_button('Update', 'na-scene-action--primary', function () {
                    Bridge.na_call('clip_scene_update', { id: scene.id });
                });
                update.title = 'Save the current clip box into ' + scene.name;
                actions.appendChild(update);
            }
            actions.appendChild(na_action_button('Rename', '', function () {
                na_clear_confirm();
                na_renaming = { id: scene.id, text: scene.name };
                na_render_scenes(na_clip);
            }));
            var confirming = na_confirm_id === scene.id;
            actions.appendChild(na_action_button(confirming ? 'Click again to delete' : 'Delete', 'na-scene-action--danger', function () {
                na_ask_delete(scene);
            }));
            row.appendChild(actions);
            list.appendChild(row);
        });

        if (!(clip.scenes || []).length) {
            list.appendChild(Shell.na_el('p', 'na-scene-empty', 'No saved scenes yet. Set up the clip box, give it a name below and press Save Current Clip.'));
        }

        document.getElementById('na-scene-save').disabled = !clip.hasBox;
        document.getElementById('na-scene-name').disabled = !clip.hasBox;
    }

    function na_save_scene() {
        var input = document.getElementById('na-scene-name');
        if (input.disabled) return;
        Bridge.na_call('clip_scene_save', { name: input.value.trim() });
        input.value = '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render From State
    // -------------------------------------------------------------------------

    ClipBox.na_render = function (state) {
        if (!state || !state.clip) return;
        na_clip = state.clip;
        if (na_renaming && !(na_clip.scenes || []).some(function (scene) { return scene.id === na_renaming.id; })) {
            na_renaming = null;
        }
        na_render_box(na_clip);
        na_render_limits(na_clip);
        na_render_scenes(na_clip);
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_wire() {
        document.getElementById('na-clip-enabled').addEventListener('change', function (event) {
            Bridge.na_call('clip_set_enabled', { enabled: event.target.checked });
        });
        document.getElementById('na-clip-edit').addEventListener('click', function () {
            Bridge.na_call('clip_toggle_edit', {});
        });
        document.getElementById('na-clip-reset').addEventListener('click', function () {
            Bridge.na_call('clip_reset', {});
        });
        document.getElementById('na-scene-save').addEventListener('click', na_save_scene);
        document.getElementById('na-scene-name').addEventListener('keydown', function (event) {
            if (event.key === 'Enter') na_save_scene();
        });
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', ClipBox.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__ClipBox = ClipBox;
})();
