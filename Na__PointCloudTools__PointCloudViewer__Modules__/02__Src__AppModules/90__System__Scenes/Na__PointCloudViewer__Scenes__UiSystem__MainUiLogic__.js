// =============================================================================
// NA POINT CLOUD VIEWER - SCENES - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
//
// FILE       : Na__PointCloudViewer__Scenes__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__PointCloudViewer__Scenes
// PURPOSE    : Scenes tab: point cloud settings saved for SketchUp scenes.
//              Press a scene to go to it (SketchUp's scene, plus which clouds
//              are shown and each one's size, opacity, colour and clip box,
//              with the budget); Update, Relink, Remove; and the export
//              settings TrueVision Sync reads (type, scale or image width,
//              dot size).
//
// SEVERAL CLOUDS (v0.10.0): a scene holds every cloud by its id. With more
//   than one cloud each card shows a chip per cloud: shown, hidden (struck
//   through), or added since the scene was saved (faded: the scene hides it
//   until it is updated).
//
// SAFETY: Update and Remove sit together at the right of each card, away from
//   Go To Scene, and each asks "Are you sure?" in a dialog first. Update shows
//   what the scene holds now against what it would become, and warns when
//   SketchUp is showing a different scene. Cancel has the focus, so Enter or
//   Escape never confirms by accident.
//
// ORDER: each card has a grip; dragging it puts the card anywhere in the list
//   (DragReorder), saved as one undoable step. TrueVision Sync shows the same
//   order, and can change it the same way.
//
// STATE: everything shown comes from state.scenes (Ruby). This file only
//   remembers what the user is in the middle of (a custom scale being typed,
//   a confirmation dialog, a relink choice), so a state push never wipes it.
//
// FRESH LIST WITHOUT OBSERVERS: the viewer never watches SketchUp's scenes.
//   Showing this tab, or the window gaining focus while it is shown, asks Ruby
//   for a fresh state, so a scene renamed or added in SketchUp appears here.
//
// =============================================================================

(function () {
    'use strict';

    var Scenes = {};
    var Shell  = window.Na__PointCloudViewer__Shell;
    var Bridge = window.Na__PointCloudViewer__Bridge;
    var DragReorder = window.Na__PointCloudViewer__DragReorder;

    var na_state         = null;    // last state.scenes
    var na_modal         = null;    // { sceneId, element, onKey } while a confirmation is open
    var na_sorter        = null;    // drag to reorder on the card list
    var na_list_waiting  = false;   // a repaint held back while a card is being dragged
    var na_custom_scale  = {};      // sceneId -> text being typed
    var na_relink_choice = {};      // sceneId -> pid picked for Relink
    var na_custom_open   = {};      // sceneId -> true while the custom scale box is shown

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

    function na_option(value, label, selected) {
        var option = Shell.na_el('option', '', label);
        option.value = String(value);
        if (selected) option.selected = true;
        return option;
    }

    function na_field(label, control) {
        var field = Shell.na_el('label', 'na-pcs-field');
        field.appendChild(Shell.na_el('span', 'na-pcs-field__label', label));
        field.appendChild(control);
        return field;
    }

    function na_tag(text, modifier) {
        return Shell.na_el('span', 'na-pcs-tag' + (modifier ? ' na-pcs-tag--' + modifier : ''), text);
    }

    function na_send_export(sceneId, values) {
        Bridge.na_call('scenes_set_export', { id: sceneId, values: values });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Export Settings Row
    // -------------------------------------------------------------------------

    function na_type_select(scene) {
        var select = Shell.na_el('select', 'naInput na-pcs-select');
        (na_state.viewTypes || []).forEach(function (type) {
            select.appendChild(na_option(type.id, type.label, type.id === scene.viewType));
        });
        select.addEventListener('change', function () { na_send_export(scene.id, { viewType: select.value }); });
        return na_field('Type', select);
    }

    function na_scale_controls(scene) {
        var wrap = Shell.na_el('div', 'na-pcs-scale');
        var select = Shell.na_el('select', 'naInput na-pcs-select');
        var presets = na_state.scalePresets || [];
        var isPreset = presets.some(function (preset) { return Number(preset.denominator) === Number(scene.scale); });
        var showCustom = !!na_custom_open[scene.id] || (scene.scale && !isPreset);
        presets.forEach(function (preset) {
            select.appendChild(na_option(preset.denominator, preset.label, !showCustom && Number(preset.denominator) === Number(scene.scale)));
        });
        select.appendChild(na_option('custom', 'Custom...', showCustom));
        wrap.appendChild(na_field('Scale', select));

        var input = Shell.na_el('input', 'naInput na-pcs-custom-scale' + (showCustom ? '' : ' na-hidden'));
        input.type = 'text';
        input.placeholder = '1:75';
        input.spellcheck = false;
        input.value = na_custom_scale[scene.id] !== undefined ? na_custom_scale[scene.id] : (scene.scale && !isPreset ? '1:' + scene.scale : '');
        input.addEventListener('input', function () { na_custom_scale[scene.id] = input.value; });
        input.addEventListener('keydown', function (event) {
            if (event.key === 'Enter') input.blur();
            if (event.key === 'Escape') { delete na_custom_scale[scene.id]; delete na_custom_open[scene.id]; na_render(); }
        });
        input.addEventListener('change', function () {
            var text = String(input.value || '').trim();
            if (!text) return;
            delete na_custom_scale[scene.id];
            na_send_export(scene.id, { scale: text });
        });
        wrap.appendChild(input);

        select.addEventListener('change', function () {
            if (select.value === 'custom') {
                na_custom_open[scene.id] = true;
                na_render();
                window.setTimeout(function () {
                    var box = document.querySelector('[data-na-pcs-custom="' + scene.id + '"]');
                    if (box) box.focus();
                }, 0);
                return;
            }
            delete na_custom_open[scene.id];
            delete na_custom_scale[scene.id];
            na_send_export(scene.id, { scale: Number(select.value) });
        });
        input.setAttribute('data-na-pcs-custom', scene.id);
        return wrap;
    }

    function na_width_select(scene) {
        var select = Shell.na_el('select', 'naInput na-pcs-select');
        var widths = (na_state.imageWidthPresets || []).slice();
        if (scene.imageWidthPx && widths.indexOf(scene.imageWidthPx) === -1) widths.push(scene.imageWidthPx);
        widths.sort(function (a, b) { return a - b; });
        widths.forEach(function (width) {
            select.appendChild(na_option(width, Shell.na_format_int(width) + ' px', width === scene.imageWidthPx));
        });
        select.addEventListener('change', function () { na_send_export(scene.id, { imageWidthPx: Number(select.value) }); });
        return na_field('Image Width', select);
    }

    function na_size_select(scene) {
        var select = Shell.na_el('select', 'naInput na-pcs-select');
        var auto = scene.pointSizePx === null || scene.pointSizePx === undefined;
        select.appendChild(na_option('auto', 'Auto (' + (auto ? scene.exportPointSizePx : '') + (auto ? ' px)' : 'from scale)'), auto));
        var max = na_state.pointSizeMaxPx || 32;
        for (var size = 1; size <= Math.min(max, 16); size += 1) {
            select.appendChild(na_option(size, size + ' px', !auto && size === scene.pointSizePx));
        }
        if (!auto && scene.pointSizePx > 16) select.appendChild(na_option(scene.pointSizePx, scene.pointSizePx + ' px', true));
        select.addEventListener('change', function () {
            na_send_export(scene.id, { pointSizePx: select.value === 'auto' ? null : Number(select.value) });
        });
        return na_field('Dot Size', select);
    }

    // What one dot and one pixel mean on paper and in the model.
    function na_export_note(scene) {
        if (scene.projection === 'perspective') {
            return 'Perspective scene: no scale. Exported at ' + Shell.na_format_int(scene.imageWidthPx || 0) +
                ' px wide with ' + scene.exportPointSizePx + ' px dots, for a matching 3D viewport.';
        }
        var pxPerMm = na_state.pxPerPaperMm || 12;
        var denominator = Number(scene.scale) || 50;
        var pixelMm = denominator / pxPerMm;
        var dotMm = pixelMm * (scene.exportPointSizePx || 1);
        return 'At ' + (scene.scaleLabel || ('1:' + denominator)) + ', one pixel is ' + na_round(pixelMm) + ' mm in the model (' +
            pxPerMm + ' px per paper mm). Dots of ' + scene.exportPointSizePx + ' px are about ' + na_round(dotMm) + ' mm.';
    }

    function na_round(value) {
        return value >= 10 ? String(Math.round(value)) : String(Math.round(value * 10) / 10);
    }

    function na_export_row(scene) {
        var row = Shell.na_el('div', 'na-pcs-export');
        row.appendChild(na_type_select(scene));
        row.appendChild(scene.projection === 'perspective' ? na_width_select(scene) : na_scale_controls(scene));
        row.appendChild(na_size_select(scene));
        return row;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Scene Card Parts
    // -------------------------------------------------------------------------

    function na_status_tags(scene) {
        var tags = [];
        tags.push(na_tag(scene.viewTypeLabel || scene.viewType, 'type'));
        tags.push(na_tag(scene.projection === 'perspective' ? Shell.na_format_int(scene.imageWidthPx || 0) + ' px' : (scene.scaleLabel || ''), 'scale'));
        if (scene.status === 'missing')  tags.push(na_tag('Missing', 'danger'));
        if (scene.status === 'noCamera') tags.push(na_tag('No camera', 'warn'));
        if (scene.isModified)            tags.push(na_tag('Settings changed', 'warn'));
        else if (scene.isActive)         tags.push(na_tag('Showing', 'active'));
        if (scene.isSelectedInSketchUp && !scene.isActive) tags.push(na_tag('SketchUp is on this scene', ''));
        return tags;
    }

    function na_cloud_chips(scene) {
        var row = Shell.na_el('div', 'na-pcs-clouds');
        (scene.clouds || []).forEach(function (cloud) {
            var chip = Shell.na_el('span', 'na-pcs-cloud' + (cloud.visible ? '' : ' na-pcs-cloud--hidden') + (cloud.known ? '' : ' na-pcs-cloud--unknown'));
            chip.style.setProperty('--na-cloud-colour', cloud.colour || '#888888');
            chip.title = !cloud.known ? cloud.name + ' was added after this scene was saved, so the scene hides it. Update the scene to include it.'
                                      : (cloud.visible ? cloud.name + ' is shown in this scene' : cloud.name + ' is hidden in this scene');
            chip.appendChild(Shell.na_el('span', 'na-cloud-dot'));
            chip.appendChild(Shell.na_el('span', 'na-pcs-cloud__name', cloud.name));
            row.appendChild(chip);
        });
        return row;
    }

    function na_relink_controls(scene) {
        var wrap = Shell.na_el('div', 'na-pcs-relink');
        var select = Shell.na_el('select', 'naInput na-pcs-select');
        var free = (na_state.pages || []).filter(function (page) { return !page.isBound; });
        if (!free.length) {
            wrap.appendChild(Shell.na_el('p', 'na-hint', 'Every SketchUp scene already has point cloud settings. Remove this one, or add a new SketchUp scene first.'));
            return wrap;
        }
        var wanted = na_relink_choice[scene.id] || scene.relinkPid || free[0].pid;
        free.forEach(function (page) {
            select.appendChild(na_option(page.pid, page.name + (page.usesCamera ? '' : ' (no camera)'), Number(page.pid) === Number(wanted)));
        });
        select.addEventListener('change', function () { na_relink_choice[scene.id] = Number(select.value); });
        wrap.appendChild(na_field('Relink to', select));
        wrap.appendChild(na_button('Relink', 'na-pcs-action na-pcs-action--primary', function () {
            Bridge.na_call('scenes_relink', { id: scene.id, pid: Number(select.value) });
            delete na_relink_choice[scene.id];
        }, 'Use these settings with the chosen SketchUp scene'));
        if (scene.relinkName) {
            wrap.appendChild(Shell.na_el('p', 'na-hint', 'A scene called "' + scene.relinkName + '" exists. It is chosen above, but nothing changes until you press Relink.'));
        }
        return wrap;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Are You Sure? (Update and Remove)
    // -------------------------------------------------------------------------

    // options: sceneId, title, paragraphs, rows ([label, value]), warning,
    //          confirmLabel, danger, onConfirm. Cancel takes the focus.
    function na_open_confirm(options) {
        na_close_confirm();
        var backdrop = Shell.na_el('div', 'na-pcs-modal');
        var card = Shell.na_el('div', 'na-pcs-modal__card');
        card.setAttribute('role', 'dialog');
        card.setAttribute('aria-modal', 'true');
        card.setAttribute('aria-labelledby', 'na-pcs-modal-title');
        var title = Shell.na_el('h3', 'na-pcs-modal__title', options.title);
        title.id = 'na-pcs-modal-title';
        card.appendChild(title);
        (options.paragraphs || []).forEach(function (text) {
            card.appendChild(Shell.na_el('p', 'na-pcs-modal__text', text));
        });
        if (options.rows && options.rows.length) {
            var grid = Shell.na_el('div', 'na-pcs-modal__compare');
            options.rows.forEach(function (row) {
                grid.appendChild(Shell.na_el('span', 'na-pcs-modal__label', row[0]));
                grid.appendChild(Shell.na_el('span', 'na-pcs-modal__value', row[1]));
            });
            card.appendChild(grid);
        }
        if (options.warning) card.appendChild(Shell.na_el('p', 'na-pcs-card__warning na-pcs-modal__warning', options.warning));

        var actions = Shell.na_el('div', 'na-pcs-modal__actions');
        var cancel = Shell.na_el('button', 'naButtonSecondary', 'Cancel');
        cancel.type = 'button';
        cancel.addEventListener('click', na_close_confirm);
        var confirm = Shell.na_el('button', 'naButton' + (options.danger ? ' na-pcs-modal__danger' : ''), options.confirmLabel);
        confirm.type = 'button';
        confirm.addEventListener('click', function () {
            na_close_confirm();
            options.onConfirm();
        });
        actions.appendChild(cancel);
        actions.appendChild(confirm);
        card.appendChild(actions);
        backdrop.appendChild(card);

        backdrop.addEventListener('click', function (event) { if (event.target === backdrop) na_close_confirm(); });
        var onKey = function (event) {
            if (event.key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                na_close_confirm();
            } else if (event.key === 'Tab') {
                // Keep the focus on the two buttons while the dialog is open.
                event.preventDefault();
                (document.activeElement === cancel ? confirm : cancel).focus();
            }
        };
        document.addEventListener('keydown', onKey, true);
        document.body.appendChild(backdrop);
        na_modal = { sceneId: options.sceneId, element: backdrop, onKey: onKey };
        cancel.focus();
    }

    function na_close_confirm() {
        if (!na_modal) return;
        document.removeEventListener('keydown', na_modal.onKey, true);
        if (na_modal.element.parentNode) na_modal.element.parentNode.removeChild(na_modal.element);
        na_modal = null;
    }

    function na_ask_update(scene) {
        var name = scene.name || '(unnamed scene)';
        var now = na_state.currentSummary || 'The settings the viewer shows now.';
        var paragraphs = [
            'The point cloud settings saved for "' + name + '" (which clouds are shown, each one\'s look and clip box, and the budget) will be replaced by what the viewer shows now. ' +
            'Type, Scale and Dot Size stay as they are, and the SketchUp scene itself is not changed.'
        ];
        if (now === scene.summary) paragraphs.push('These look the same as the saved settings.');
        paragraphs.push('Edit, Undo in SketchUp puts the old settings back.');
        var warning = null;
        if (!scene.isSelectedInSketchUp) {
            var showing = (na_state.pages || []).filter(function (page) { return page.isSelected; })[0];
            warning = (showing ? 'SketchUp is showing "' + showing.name + '" right now, not "' + name + '". '
                               : 'SketchUp is not showing "' + name + '" right now. ') +
                      'Check the cloud is set up for "' + name + '" before you update it.';
        }
        na_open_confirm({
            sceneId: scene.id,
            title: 'Update "' + name + '"?',
            paragraphs: paragraphs,
            rows: [['Saved now', scene.summary || ''], ['Will become', now]],
            warning: warning,
            confirmLabel: 'Update Scene',
            onConfirm: function () { Bridge.na_call('scenes_update', { id: scene.id }); }
        });
    }

    function na_ask_remove(scene) {
        var name = scene.name || '(unnamed scene)';
        na_open_confirm({
            sceneId: scene.id,
            title: 'Remove "' + name + '"?',
            paragraphs: [
                'The point cloud settings saved for "' + name + '" will be removed: budget, size, opacity, colour, clip box, ' +
                'Type, Scale and Dot Size. TrueVision Sync will no longer export this scene.',
                'The SketchUp scene itself is not changed. Edit, Undo in SketchUp brings the settings back.'
            ],
            rows: [['Saved now', scene.summary || '']],
            confirmLabel: 'Remove Settings',
            danger: true,
            onConfirm: function () { Bridge.na_call('scenes_remove', { id: scene.id }); }
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Scene Card
    // -------------------------------------------------------------------------

    function na_scene_card(scene, sortable) {
        var card = Shell.na_el('div', 'na-pcs-card' + (scene.isActive ? ' na-pcs-card--active' : '') +
                                      (scene.status === 'missing' ? ' na-pcs-card--missing' : ''));
        card.setAttribute('data-na-sort-id', scene.id);
        var header = Shell.na_el('div', 'na-pcs-card__header');
        if (sortable) header.appendChild(DragReorder.na_grip(scene.name));
        var name = na_button(scene.name || '(unnamed scene)', 'na-pcs-card__name', function () {
            Bridge.na_call('scenes_recall', { id: scene.id });
        }, scene.status === 'missing' ? 'This SketchUp scene no longer exists' : 'Go to ' + scene.name);
        name.disabled = scene.status === 'missing' || !!na_state.readonly;
        header.appendChild(name);
        var tags = Shell.na_el('div', 'na-pcs-card__tags');
        na_status_tags(scene).forEach(function (tag) { tags.appendChild(tag); });
        header.appendChild(tags);
        card.appendChild(header);

        if ((na_state.cloudCount || 0) > 1 && (scene.clouds || []).length) card.appendChild(na_cloud_chips(scene));
        card.appendChild(Shell.na_el('p', 'na-pcs-card__summary', scene.summary || ''));
        (scene.warnings || []).forEach(function (text) {
            card.appendChild(Shell.na_el('p', 'na-pcs-card__warning', text));
        });

        if (!na_state.readonly) {
            if (scene.status === 'missing') card.appendChild(na_relink_controls(scene));
            card.appendChild(na_export_row(scene));
            card.appendChild(Shell.na_el('p', 'na-hint na-pcs-card__note', na_export_note(scene)));

            // Go To Scene on the left; the two that change the record on the
            // right, each behind an Are You Sure? dialog.
            var actions = Shell.na_el('div', 'na-pcs-card__actions');
            if (scene.status !== 'missing') {
                actions.appendChild(na_button('Go To Scene', 'na-pcs-action na-pcs-action--primary', function () {
                    Bridge.na_call('scenes_recall', { id: scene.id });
                }));
            }
            var changes = Shell.na_el('div', 'na-pcs-card__changes');
            if (scene.status !== 'missing') {
                changes.appendChild(na_button('Update', 'na-pcs-action' + (scene.isModified ? ' na-pcs-action--modified' : ''), function () {
                    na_ask_update(scene);
                }, 'Save the cloud\'s current settings and clip box into ' + scene.name + '. Asks first. The SketchUp scene itself is not changed.'));
            }
            changes.appendChild(na_button('Remove', 'na-pcs-action na-pcs-action--danger', function () {
                na_ask_remove(scene);
            }, 'Forget these point cloud settings. Asks first. The SketchUp scene is not changed.'));
            actions.appendChild(changes);
            card.appendChild(actions);
        }
        if (scene.updatedText) card.appendChild(Shell.na_el('p', 'na-pcs-card__time', scene.updatedText));
        return card;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | List + Add
    // -------------------------------------------------------------------------

    function na_render_list() {
        var list = document.getElementById('na-pcs-list');
        if (!list) return;
        // A card is being dragged: the list repaints when it is dropped
        if (na_sorter && na_sorter.na_is_dragging()) { na_list_waiting = true; return; }
        list.innerHTML = '';
        var scenes = na_state.scenes || [];
        var sortable = scenes.length > 1 && !na_state.readonly;
        scenes.forEach(function (scene) { list.appendChild(na_scene_card(scene, sortable)); });
        if (!scenes.length) {
            list.appendChild(Shell.na_el('p', 'na-scene-empty', 'No point cloud scenes yet. Set the cloud up for a SketchUp scene, then save its settings below.'));
        }
        var pages = na_state.pages || [];
        Shell.na_text('na-pcs-count', scenes.length + ' of ' + pages.length + ' SketchUp scene' + (pages.length === 1 ? '' : 's'));
        if (na_sorter) na_sorter.na_after_render();
    }

    function na_render_add() {
        var select = document.getElementById('na-pcs-add-select');
        var button = document.getElementById('na-pcs-add-go');
        var hint   = document.getElementById('na-pcs-add-hint');
        if (!select || !button) return;
        var previous = select.value;
        select.innerHTML = '';
        var free = (na_state.pages || []).filter(function (page) { return !page.isBound; });
        var selected = free.filter(function (page) { return page.isSelected; })[0];
        var keep = free.some(function (page) { return String(page.pid) === previous; }) ? previous : null;
        free.forEach(function (page) {
            var label = page.name + (page.usesCamera ? '' : ' (no camera)') + (page.isSelected ? ' (showing now)' : '');
            select.appendChild(na_option(page.pid, label, keep ? String(page.pid) === keep : (selected ? page.pid === selected.pid : false)));
        });
        var pages = na_state.pages || [];
        var usable = free.length > 0 && !na_state.readonly;
        select.disabled = !usable;
        button.disabled = !usable;
        if (!pages.length) {
            hint.textContent = 'This model has no SketchUp scenes yet. Add one in SketchUp (Window, Scenes), then come back.';
        } else if (!free.length) {
            hint.textContent = 'Every SketchUp scene already has point cloud settings.';
        } else if (!na_state.hasCloud) {
            hint.textContent = 'No point cloud is loaded. Settings can still be saved, but load the cloud to see what you save.';
        } else {
            hint.textContent = 'Saves the settings shown now. The SketchUp scene itself is never changed.';
        }
    }

    function na_render() {
        if (!na_state) return;
        var problem = document.getElementById('na-pcs-problem');
        if (problem) {
            problem.textContent = na_state.problem || '';
            problem.classList.toggle('na-hidden', !na_state.problem);
        }
        if (!na_state.isAvailable) {
            var list = document.getElementById('na-pcs-list');
            if (list) list.innerHTML = '';
            return;
        }
        na_render_list();
        na_render_add();
    }

    Scenes.na_render = function (state) {
        if (!state || !state.scenes) return;
        na_state = state.scenes;
        var ids = (na_state.scenes || []).map(function (scene) { return scene.id; });
        if (na_modal && ids.indexOf(na_modal.sceneId) === -1) na_close_confirm();
        na_render();
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Wiring
    // -------------------------------------------------------------------------

    function na_tab_is_active() {
        return window.Na_TabRouter && window.Na_TabRouter.na_get_active_tab() === 'scenes';
    }

    function na_wire() {
        document.getElementById('na-pcs-add-go').addEventListener('click', function () {
            var select = document.getElementById('na-pcs-add-select');
            if (!select.value) return;
            Bridge.na_call('scenes_add', { pid: Number(select.value) });
        });
        na_sorter = DragReorder.na_attach(document.getElementById('na-pcs-list'), {
            canDrag: function () {
                return !!na_state && !na_state.readonly && !na_modal && (na_state.scenes || []).length > 1;
            },
            onReorder: function (ids) { Bridge.na_call('scenes_reorder', { ids: ids }); },
            onEnd: function (changed) {
                var waiting = na_list_waiting;
                na_list_waiting = false;
                // After a change Ruby pushes the new order; otherwise catch up now
                if (waiting && !changed && na_state) na_render();
            }
        });
        window.addEventListener('focus', function () {
            if (na_tab_is_active()) Bridge.na_call('state_refresh', {});
        });
        var hook = function () {
            if (!window.Na_TabRouter) return false;
            window.Na_TabRouter.na_on_change(function (tabId) {
                if (tabId === 'scenes') Bridge.na_call('state_refresh', {});
            });
            return true;
        };
        if (!hook()) window.setTimeout(hook, 0);   // the router loads after this file
    }

    // endregion ----------------------------------------------------------------

    Shell.na_on('state', Scenes.na_render);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_wire);
    } else {
        na_wire();
    }

    window.Na__PointCloudViewer__Scenes = Scenes;
})();
