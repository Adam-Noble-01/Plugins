// =============================================================================
// NA NOBLE3D MODELLING TOOLS - MEGA EXPLODE - UI BRIDGE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__MegaExplode__UiBridge__.js
// NAMESPACE  : window.Na__MegaExplode__* (Ruby-facing entry points)
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Render live selection stats and cleanup toggles, show the
//              in-dialog confirm modal, then send the explode request to Ruby
// CREATED    : 2026
//
// RUBY -> JS : Na__MegaExplode__ReceivePayload(payload)
//              Na__MegaExplode__ReceiveSelection(selection)
//              Na__MegaExplode__ReceiveStatus(message, variant)
// JS -> RUBY : sketchup.na_dialog_ready / na_refresh / na_set_options
//              sketchup.na_explode      / na_js_log
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var naState = {
        selection : null,
        settings  : {
            move_to_untagged : false,
            strip_materials  : false,
            delete_faces     : false,
            delete_hidden    : false,
            unlock_locked    : false,
            purge_unused     : false
        },
        exploding : false
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function na_el(elementId) { return document.getElementById(elementId); }

    function na_setText(elementId, textValue) {
        var element = na_el(elementId);
        if (element) { element.textContent = textValue; }
    }

    function na_setModifier(element, modifierClass, isOn) {
        if (!element) { return; }
        if (isOn) {
            element.classList.add(modifierClass);
        } else {
            element.classList.remove(modifierClass);
        }
    }

    function na_log(message) {
        if (window.sketchup && window.sketchup.na_js_log) {
            window.sketchup.na_js_log(String(message));
        }
    }

    function na_callRuby(callbackName, argumentValue) {
        if (!window.sketchup || !window.sketchup[callbackName]) { return; }

        if (arguments.length > 1) {
            window.sketchup[callbackName](argumentValue);
        } else {
            window.sketchup[callbackName]();
        }
    }

    function na_formatNumber(numberValue) {
        return String(numberValue || 0).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    function na_pluralise(countValue, singularWord, pluralWord) {
        return countValue === 1 ? singularWord : pluralWord;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Settings
    // -------------------------------------------------------------------------

    function na_currentOptions() {
        return {
            move_to_untagged : !!naState.settings.move_to_untagged,
            strip_materials  : !!naState.settings.strip_materials,
            delete_faces     : !!naState.settings.delete_faces,
            delete_hidden    : !!naState.settings.delete_hidden,
            unlock_locked    : !!naState.settings.unlock_locked,
            purge_unused     : !!naState.settings.purge_unused
        };
    }

    function na_readCheckboxIntoState() {
        naState.settings.move_to_untagged = !!(na_el('naMegaExplode_moveToUntagged') && na_el('naMegaExplode_moveToUntagged').checked);
        naState.settings.strip_materials  = !!(na_el('naMegaExplode_stripMaterials') && na_el('naMegaExplode_stripMaterials').checked);
        naState.settings.delete_faces     = !!(na_el('naMegaExplode_deleteFaces') && na_el('naMegaExplode_deleteFaces').checked);
        naState.settings.delete_hidden    = !!(na_el('naMegaExplode_deleteHidden') && na_el('naMegaExplode_deleteHidden').checked);
        naState.settings.unlock_locked     = !!(na_el('naMegaExplode_unlockLocked') && na_el('naMegaExplode_unlockLocked').checked);
        naState.settings.purge_unused     = !!(na_el('naMegaExplode_purgeUnused') && na_el('naMegaExplode_purgeUnused').checked);
    }

    function na_renderSettings(settingsPayload) {
        if (!settingsPayload) { return; }

        naState.settings.move_to_untagged = !!settingsPayload.move_to_untagged;
        naState.settings.strip_materials  = !!settingsPayload.strip_materials;
        naState.settings.delete_faces     = !!settingsPayload.delete_faces;
        naState.settings.delete_hidden    = !!settingsPayload.delete_hidden;
        naState.settings.unlock_locked    = !!settingsPayload.unlock_locked;
        naState.settings.purge_unused     = !!settingsPayload.purge_unused;

        na_setChecked('naMegaExplode_moveToUntagged', naState.settings.move_to_untagged);
        na_setChecked('naMegaExplode_stripMaterials',  naState.settings.strip_materials);
        na_setChecked('naMegaExplode_deleteFaces',     naState.settings.delete_faces);
        na_setChecked('naMegaExplode_deleteHidden',    naState.settings.delete_hidden);
        na_setChecked('naMegaExplode_unlockLocked',   naState.settings.unlock_locked);
        na_setChecked('naMegaExplode_purgeUnused',   naState.settings.purge_unused);
    }

    function na_setChecked(elementId, isChecked) {
        var element = na_el(elementId);
        if (element) { element.checked = !!isChecked; }
    }

    function na_postOptions() {
        na_readCheckboxIntoState();
        na_callRuby('na_set_options', JSON.stringify(na_currentOptions()));
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Selection Rendering
    // -------------------------------------------------------------------------

    function na_renderSelection(selectionPayload) {
        naState.selection = selectionPayload || null;

        var selection = naState.selection || {};
        na_setStat('naMegaExplode_statGroups',     'naMegaExplode_statGroupsWrap',     selection.group_count);
        na_setStat('naMegaExplode_statComponents', 'naMegaExplode_statComponentsWrap', selection.component_count);
        na_setStat('naMegaExplode_statDepth',       'naMegaExplode_statDepthWrap',      selection.deepest_level);
        na_setStat('naMegaExplode_statFaces',      'naMegaExplode_statFacesWrap',      selection.face_count);
        na_setStat('naMegaExplode_statEdges',      'naMegaExplode_statEdgesWrap',      selection.edge_count);
        na_setStat('naMegaExplode_statLocked',     'naMegaExplode_statLockedWrap',     selection.locked_container_count);

        na_setText('naMegaExplode_statSelected',    na_formatNumber(selection.selected_count));
        na_setText('naMegaExplode_statDefinitions', na_formatNumber(selection.unique_definition_count));
        na_setText('naMegaExplode_statTagged',     na_formatNumber(selection.tagged_entity_count));
        na_setText('naMegaExplode_statTags',      na_formatNumber(selection.unique_tag_count));
        na_setText('naMegaExplode_statMaterials',  na_formatNumber(selection.unique_material_count));
        na_setText('naMegaExplode_statOthers',    na_formatNumber(selection.other_instance_count));

        na_renderNotes(selection);
        na_updateExplodeButton();
    }

    function na_setStat(valueId, wrapId, countValue) {
        na_setText(valueId, na_formatNumber(countValue));
        na_setModifier(na_el(wrapId), 'naMegaExplode__Stat--zero', !countValue);
    }

    function na_renderNotes(selection) {
        var notesElement = na_el('naMegaExplode_selectionNotes');
        if (!notesElement) { return; }

        notesElement.innerHTML = '';
        na_selectionNotes(selection).forEach(function (note) {
            var noteElement = document.createElement('div');
            noteElement.className = 'naMegaExplode__Note' + (note.warn ? ' naMegaExplode__Note--warn' : '');
            noteElement.textContent = note.text;
            notesElement.appendChild(noteElement);
        });
    }

    function na_selectionNotes(selection) {
        var notes = [];
        if (!selection || !selection.has_selection) {
            notes.push({ warn: true, text: 'Nothing is selected. Select groups or components in the model.' });
            return notes;
        }

        if ((selection.container_count || 0) === 0) {
            notes.push({ warn: true, text: 'The selection has no groups or components to explode.' });
        } else {
            notes.push({
                warn: false,
                text: 'Will recursively explode ' +
                    na_formatNumber(selection.container_count) + ' ' +
                    na_pluralise(selection.container_count, 'container', 'containers') +
                    ' across ' +
                    na_formatNumber(selection.deepest_level) + ' ' +
                    na_pluralise(selection.deepest_level, 'level', 'levels') + '.'
            });
        }

        if (selection.locked_container_count > 0) {
            notes.push({
                warn: true,
                text: na_formatNumber(selection.locked_container_count) + ' locked ' +
                    na_pluralise(selection.locked_container_count, 'container is', 'containers are') +
                    ' in the tree. Turn on Unlock locked containers first, or they will be skipped.'
            });
        }

        if (selection.other_instance_count > 0) {
            notes.push({
                warn: false,
                text: na_formatNumber(selection.other_instance_count) + ' other ' +
                    na_pluralise(selection.other_instance_count, 'placement', 'placements') +
                    ' of the same definitions stay intact. Exploding an instance does not change the others.'
            });
        }

        if (selection.image_count > 0) {
            notes.push({
                warn: false,
                text: na_formatNumber(selection.image_count) + ' nested ' +
                    na_pluralise(selection.image_count, 'image is', 'images are') +
                    ' left as images.'
            });
        }

        if (selection.limit_reached) {
            notes.push({
                warn: true,
                text: 'Preview stopped at ' + na_formatNumber(selection.preview_limit) +
                    ' entities. The explode itself still walks the full selection.'
            });
        }

        return notes;
    }

    function na_canExplode() {
        var selection = naState.selection;
        return !!(selection && selection.has_selection && selection.container_count > 0 && !naState.exploding);
    }

    function na_updateExplodeButton() {
        var button = na_el('naMegaExplode_btnExplode');
        if (!button) { return; }

        var canExplode = na_canExplode();
        button.disabled = !canExplode;

        if (!naState.selection || !naState.selection.has_selection) {
            button.textContent = 'Explode Selection...';
            return;
        }

        var containerCount = naState.selection.container_count || 0;
        button.textContent = canExplode
            ? ('Explode ' + na_formatNumber(containerCount) + ' ' +
               na_pluralise(containerCount, 'Container', 'Containers') + '...')
            : 'Explode Selection...';
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Confirm Modal
    // -------------------------------------------------------------------------

    function na_openModal() {
        if (!na_canExplode()) { return; }

        var modal = na_el('naMegaExplode_modal');
        var body  = na_el('naMegaExplode_modalBody');
        if (!modal || !body) { return; }

        body.innerHTML = na_modalBodyHtml();
        modal.classList.add('is-open');
        var confirmButton = na_el('naMegaExplode_btnConfirm');
        if (confirmButton) { confirmButton.focus(); }
    }

    function na_closeModal() {
        var modal = na_el('naMegaExplode_modal');
        if (!modal) { return; }

        modal.classList.remove('is-open');
    }

    function na_modalBodyHtml() {
        var selection = naState.selection || {};
        var options   = na_currentOptions();
        var untagged  = selection.untagged_display_name || 'Untagged';
        var lines = [];

        lines.push('<p>This will recursively explode every group and component in the current selection, including all nested levels.</p>');
        lines.push('<p><strong>' +
            na_formatNumber(selection.container_count) + '</strong> ' +
            na_pluralise(selection.container_count, 'container', 'containers') +
            ' across <strong>' +
            na_formatNumber(selection.deepest_level) + '</strong> ' +
            na_pluralise(selection.deepest_level, 'level', 'levels') +
            '.</p>');

        if (selection.locked_container_count > 0) {
            lines.push('<p>' + (options.unlock_locked
                ? 'Locked containers will be unlocked, then exploded.'
                : (na_formatNumber(selection.locked_container_count) + ' locked ' +
                   na_pluralise(selection.locked_container_count, 'container', 'containers') +
                   ' will be skipped.')) + '</p>');
        }

        var extras = [];
        if (options.move_to_untagged) { extras.push('move remaining geometry to ' + untagged); }
        if (options.strip_materials)  { extras.push('strip front, back and edge materials to Default'); }
        if (options.delete_faces)     { extras.push('delete all faces and surfaces'); }
        if (options.delete_hidden)    { extras.push('delete hidden geometry'); }
        if (options.purge_unused)     { extras.push('purge unused components, materials and tags'); }
        if (extras.length > 0) {
            lines.push('<p>Cleanup: ' + extras.join('; ') + '.</p>');
        }

        lines.push('<p>Use SketchUp Undo to reverse the whole operation.</p>');
        return lines.join('');
    }

    function na_confirmExplode() {
        if (!na_canExplode()) {
            na_closeModal();
            return;
        }

        naState.exploding = true;
        na_updateExplodeButton();
        Na__MegaExplode__ReceiveStatus('Exploding...', 'info');
        na_closeModal();
        na_callRuby('na_explode', JSON.stringify(na_currentOptions()));
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Event Wiring
    // -------------------------------------------------------------------------

    function na_bindEvents() {
        var refreshElement = na_el('naMegaExplode_btnRefresh');
        var explodeElement  = na_el('naMegaExplode_btnExplode');
        var cancelElement   = na_el('naMegaExplode_btnCancel');
        var confirmElement  = na_el('naMegaExplode_btnConfirm');
        var modalElement    = na_el('naMegaExplode_modal');

        if (refreshElement) {
            refreshElement.addEventListener('click', function () {
                na_callRuby('na_refresh');
            });
        }

        if (explodeElement) {
            explodeElement.addEventListener('click', function () {
                if (explodeElement.disabled) { return; }
                na_readCheckboxIntoState();
                na_openModal();
            });
        }

        if (cancelElement) {
            cancelElement.addEventListener('click', function () {
                na_closeModal();
            });
        }

        if (confirmElement) {
            confirmElement.addEventListener('click', function () {
                na_confirmExplode();
            });
        }

        if (modalElement) {
            modalElement.addEventListener('click', function (event) {
                if (event.target === modalElement) { na_closeModal(); }
            });
        }

        ['naMegaExplode_moveToUntagged', 'naMegaExplode_stripMaterials',
         'naMegaExplode_deleteFaces', 'naMegaExplode_deleteHidden',
         'naMegaExplode_unlockLocked', 'naMegaExplode_purgeUnused'].forEach(function (elementId) {
            var element = na_el(elementId);
            if (!element) { return; }
            element.addEventListener('change', na_postOptions);
        });

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') { na_closeModal(); }
        });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Ruby Facing Entry Points
    // -------------------------------------------------------------------------

    window.Na__MegaExplode__ReceivePayload = function (payload) {
        naState.exploding = false;
        if (!payload) { return; }

        na_renderSettings(payload.settings);
        na_renderSelection(payload.selection);
    };

    window.Na__MegaExplode__ReceiveSelection = function (selectionPayload) {
        na_renderSelection(selectionPayload);
    };

    window.Na__MegaExplode__ReceiveStatus = function (message, variant) {
        var statusElement = na_el('naMegaExplode_status');
        if (!statusElement) { return; }

        statusElement.textContent = message;
        statusElement.className   = 'naMegaExplode__StatusText' +
            (variant && variant !== 'info' ? ' naMegaExplode__StatusText--' + variant : '');
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Boot
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function () {
        na_bindEvents();
        na_updateExplodeButton();
        na_log('Mega Explode dialog ready.');
        na_callRuby('na_dialog_ready');
    });

    // endregion ---------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
