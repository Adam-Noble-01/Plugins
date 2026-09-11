// =============================================================================
// NA NOBLE3D MODELLING TOOLS - GROUP / COMPONENT CONVERTER - UI BRIDGE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__GroupComponentConverter__UiBridge__.js
// NAMESPACE  : window.Na__GroupComponentConverter__* (Ruby-facing entry points)
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Drive the direction and reach switches, render the live
//              conversion preview and nesting report, show the confirm
//              modal, then send the conversion request to Ruby
// CREATED    : 2026
//
// Every selection payload carries a plan for both directions at both reaches,
// so flipping a switch redraws from data already here. Toggles change the
// plan itself, so they post back to Ruby, which rescans and pushes again.
//
// RUBY -> JS : Na__GroupComponentConverter__ReceivePayload(payload)
//              Na__GroupComponentConverter__ReceiveSelection(selection)
//              Na__GroupComponentConverter__ReceiveStatus(message, variant)
// JS -> RUBY : sketchup.na_dialog_ready / na_refresh / na_set_options
//              sketchup.na_convert      / na_js_log
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Constants and Module State
    // -------------------------------------------------------------------------

    var NA_DIRECTION_GROUPS_TO_COMPONENTS = 'groups_to_components';
    var NA_DIRECTION_COMPONENTS_TO_GROUPS = 'components_to_groups';
    var NA_SCOPE_CURRENT_LEVEL            = 'current_level';
    var NA_SCOPE_DEEP_NESTING             = 'deep_nesting';
    var NA_ARROW                          = '\u2192';
    var NA_DOT                            = ' \u00b7 ';

    var NA_SCOPE_HINTS = {
        groups_to_components: {
            current_level : 'Converts only the groups selected at the current level. ' +
                            'Anything nested inside them is left as it is.',
            deep_nesting  : 'Converts the selected groups and every group nested inside groups and ' +
                            'components, at every level. A group inside a shared component converts ' +
                            'once, and every placement of that component follows.'
        },
        components_to_groups: {
            current_level : 'Converts only the components selected at the current level. ' +
                            'Their contents are copied into the new groups unchanged.',
            deep_nesting  : 'Converts the selected components and every component nested inside them ' +
                            'or inside groups, at every level. Each becomes an independent group; other ' +
                            'placements of the same components stay components.'
        }
    };

    var naState = {
        selection  : null,
        settings   : {
            direction           : NA_DIRECTION_GROUPS_TO_COMPONENTS,
            scope               : NA_SCOPE_CURRENT_LEVEL,
            merge_common_groups : false,
            merge_group_copies  : true,
            include_locked      : false
        },
        converting : false
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

    function na_countLabel(countValue, singularWord, pluralWord) {
        return na_formatNumber(countValue) + ' ' + na_pluralise(countValue, singularWord, pluralWord);
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Switch and Plan Lookups
    // -------------------------------------------------------------------------

    function na_isGroupsToComponents() {
        return naState.settings.direction === NA_DIRECTION_GROUPS_TO_COMPONENTS;
    }

    function na_isDeep() {
        return naState.settings.scope === NA_SCOPE_DEEP_NESTING;
    }

    function na_words() {
        return na_isGroupsToComponents()
            ? { from: 'group', froms: 'groups', to: 'component', tos: 'components', From: 'Group', Froms: 'Groups', Tos: 'Components' }
            : { from: 'component', froms: 'components', to: 'group', tos: 'groups', From: 'Component', Froms: 'Components', Tos: 'Groups' };
    }

    function na_planFor(direction, scope) {
        var selection = naState.selection;
        if (!selection || !selection.plans || !selection.plans[direction]) { return {}; }

        return selection.plans[direction][scope] || {};
    }

    function na_currentPlan() {
        return na_planFor(naState.settings.direction, naState.settings.scope);
    }

    function na_otherScopePlan() {
        var otherScope = na_isDeep() ? NA_SCOPE_CURRENT_LEVEL : NA_SCOPE_DEEP_NESTING;
        return na_planFor(naState.settings.direction, otherScope);
    }

    function na_convertCount() {
        return na_currentPlan().convert_count || 0;
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Settings
    // -------------------------------------------------------------------------

    function na_currentOptions() {
        return {
            direction           : naState.settings.direction,
            scope               : naState.settings.scope,
            merge_common_groups : !!naState.settings.merge_common_groups,
            merge_group_copies  : !!naState.settings.merge_group_copies,
            include_locked      : !!naState.settings.include_locked
        };
    }

    function na_checkedRadioValue(groupName, fallbackValue) {
        var checked = document.querySelector('input[name="' + groupName + '"]:checked');
        return checked ? checked.value : fallbackValue;
    }

    function na_isChecked(elementId) {
        var element = na_el(elementId);
        return !!(element && element.checked);
    }

    function na_setChecked(elementId, isChecked) {
        var element = na_el(elementId);
        if (element) { element.checked = !!isChecked; }
    }

    function na_readControlsIntoState() {
        naState.settings.direction           = na_checkedRadioValue('naConverter_direction', naState.settings.direction);
        naState.settings.scope               = na_checkedRadioValue('naConverter_scope', naState.settings.scope);
        naState.settings.merge_common_groups = na_isChecked('naConverter_mergeCommon');
        naState.settings.merge_group_copies  = na_isChecked('naConverter_mergeCopies');
        naState.settings.include_locked      = na_isChecked('naConverter_includeLocked');
    }

    function na_renderSettings(settingsPayload) {
        if (!settingsPayload) { return; }

        naState.settings.direction = settingsPayload.direction === NA_DIRECTION_COMPONENTS_TO_GROUPS
            ? NA_DIRECTION_COMPONENTS_TO_GROUPS : NA_DIRECTION_GROUPS_TO_COMPONENTS;
        naState.settings.scope = settingsPayload.scope === NA_SCOPE_DEEP_NESTING
            ? NA_SCOPE_DEEP_NESTING : NA_SCOPE_CURRENT_LEVEL;
        naState.settings.merge_common_groups = !!settingsPayload.merge_common_groups;
        naState.settings.merge_group_copies  = !!settingsPayload.merge_group_copies;
        naState.settings.include_locked      = !!settingsPayload.include_locked;

        na_setChecked('naConverter_dirGroupsToComponents', na_isGroupsToComponents());
        na_setChecked('naConverter_dirComponentsToGroups', !na_isGroupsToComponents());
        na_setChecked('naConverter_scopeCurrent',          !na_isDeep());
        na_setChecked('naConverter_scopeDeep',             na_isDeep());
        na_setChecked('naConverter_mergeCommon',           naState.settings.merge_common_groups);
        na_setChecked('naConverter_mergeCopies',           naState.settings.merge_group_copies);
        na_setChecked('naConverter_includeLocked',         naState.settings.include_locked);
    }

    function na_updateOptionVisibility() {
        var groupOptions = na_el('naConverter_groupOptions');
        if (groupOptions) { groupOptions.hidden = !na_isGroupsToComponents(); }

        var commonOn    = !!naState.settings.merge_common_groups;
        var copiesInput = na_el('naConverter_mergeCopies');
        if (copiesInput) { copiesInput.disabled = commonOn; }
        na_setModifier(na_el('naConverter_mergeCopiesRow'), 'naConverter__Check--disabled', commonOn);
        na_setText('naConverter_mergeCopiesHint', commonOn
            ? 'Included while Common groups is on: group copies always share geometry.'
            : 'Groups still sharing one definition (copied and never edited) become instances ' +
              'of a single component. Off: every group gets its own component definition.');
    }

    function na_postOptions() {
        na_callRuby('na_set_options', JSON.stringify(na_currentOptions()));
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Rendering - Switch Hint and Preview
    // -------------------------------------------------------------------------

    function na_renderAll() {
        na_updateOptionVisibility();
        na_renderScopeHint();
        na_renderPreview();
        na_renderSelectionStats();
        na_renderLevels();
        na_renderNotes('naConverter_planNotes', na_planNotes());
        na_renderNotes('naConverter_selectionNotes', na_selectionNotes());
        na_updateConvertButton();
    }

    function na_renderScopeHint() {
        var hints = NA_SCOPE_HINTS[naState.settings.direction] || {};
        na_setText('naConverter_scopeHint', hints[naState.settings.scope] || '');
    }

    function na_renderPreview() {
        var plan  = na_currentPlan();
        var words = na_words();
        var count = plan.convert_count || 0;

        na_setText('naConverter_previewCount', na_formatNumber(count));
        na_setText('naConverter_previewFrom', na_pluralise(count, words.from, words.froms));
        na_setText('naConverter_previewTo', na_pluralise(count, words.to, words.tos));
        na_setModifier(na_el('naConverter_preview'), 'naConverter__Preview--zero', count === 0);
        na_setText('naConverter_previewSplit', na_previewSplitText(plan));
    }

    function na_previewSplitText(plan) {
        if (!naState.selection || !naState.selection.has_selection) { return ''; }

        if (!na_isDeep()) {
            var deeperCount = (na_otherScopePlan().convert_count || 0) - (plan.convert_count || 0);
            return deeperCount > 0
                ? ('At the current level only' + NA_DOT + na_formatNumber(deeperCount) + ' more nested below')
                : 'At the current level only';
        }

        return na_formatNumber(plan.top_level_count) + ' at the current level' + NA_DOT +
            na_formatNumber(plan.nested_count) + ' nested';
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Rendering - Selection Report
    // -------------------------------------------------------------------------

    function na_renderSelectionStats() {
        var selection = naState.selection || {};

        na_setStat('naConverter_statGroups',     'naConverter_statGroupsWrap',     selection.group_count);
        na_setStat('naConverter_statComponents', 'naConverter_statComponentsWrap', selection.component_count);
        na_setStat('naConverter_statDepth',      'naConverter_statDepthWrap',      selection.deepest_level);

        na_setText('naConverter_statTopGroups',        na_formatNumber(selection.top_group_count));
        na_setText('naConverter_statTopComponents',    na_formatNumber(selection.top_component_count));
        na_setText('naConverter_statNestedGroups',     na_formatNumber(selection.nested_group_count));
        na_setText('naConverter_statNestedComponents', na_formatNumber(selection.nested_component_count));
        na_setText('naConverter_statDefinitions',      na_formatNumber(selection.unique_component_definition_count));
        na_setText('naConverter_statLocked',           na_formatNumber(selection.locked_container_count));
    }

    function na_setStat(valueId, wrapId, countValue) {
        na_setText(valueId, na_formatNumber(countValue));
        na_setModifier(na_el(wrapId), 'naConverter__Stat--zero', !countValue);
    }

    function na_renderLevels() {
        var body = na_el('naConverter_levelRows');
        if (!body) { return; }

        body.innerHTML = '';
        var rows = (naState.selection && naState.selection.levels) || [];
        if (rows.length === 0) {
            var emptyRow  = document.createElement('tr');
            var emptyCell = document.createElement('td');
            emptyCell.colSpan   = 3;
            emptyCell.className = 'naConverter__Cell--empty';
            emptyCell.textContent = 'No groups or components in the selection.';
            emptyRow.appendChild(emptyCell);
            body.appendChild(emptyRow);
            return;
        }

        rows.forEach(function (row, index) {
            body.appendChild(na_levelRowElement(row, index === 0));
        });
    }

    function na_levelRowElement(row, isCurrentLevel) {
        var inReach   = isCurrentLevel || na_isDeep();
        var rowEl     = document.createElement('tr');
        var labelCell = document.createElement('td');

        labelCell.textContent = row.label;
        if (isCurrentLevel) {
            var tag = document.createElement('span');
            tag.className   = 'naConverter__LevelTag';
            tag.textContent = '(current)';
            labelCell.appendChild(tag);
        }

        rowEl.appendChild(labelCell);
        rowEl.appendChild(na_levelCell(row.groups,     inReach && na_isGroupsToComponents()));
        rowEl.appendChild(na_levelCell(row.components, inReach && !na_isGroupsToComponents()));
        return rowEl;
    }

    function na_levelCell(countValue, isTarget) {
        var cell = document.createElement('td');
        cell.textContent = na_formatNumber(countValue);
        if (!countValue) {
            cell.className = 'naConverter__Cell--zero';
        } else if (isTarget) {
            cell.className = 'naConverter__Cell--target';
        }
        return cell;
    }

    function na_renderNotes(listId, notes) {
        var listElement = na_el(listId);
        if (!listElement) { return; }

        listElement.innerHTML = '';
        notes.forEach(function (note) {
            var noteElement = document.createElement('div');
            noteElement.className = 'naConverter__Note' + (note.warn ? ' naConverter__Note--warn' : '');
            noteElement.textContent = note.text;
            listElement.appendChild(noteElement);
        });
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Notes
    // -------------------------------------------------------------------------

    function na_planNotes() {
        var selection = naState.selection;
        var notes = [];

        if (!selection || !selection.has_selection) {
            notes.push({ warn: true, text: 'Nothing is selected. Select groups or components in the model.' });
            return notes;
        }

        var plan  = na_currentPlan();
        var words = na_words();

        if (!plan.convert_count) {
            na_pushNothingToConvertNote(notes, words);
        }

        if (plan.locked_skipped_count > 0 && !naState.settings.include_locked) {
            notes.push({
                warn: true,
                text: na_countLabel(plan.locked_skipped_count, 'locked container is', 'locked containers are') +
                    ' skipped with everything inside. Turn on Include locked containers to convert them.'
            });
        }

        if (na_isGroupsToComponents()) {
            na_pushGroupsToComponentsNotes(notes, plan);
        } else {
            na_pushComponentsToGroupsNotes(notes, plan);
        }

        if (selection.limit_reached) {
            notes.push({
                warn: true,
                text: 'Preview stopped at ' + na_formatNumber(selection.preview_limit) +
                    ' containers, so these counts are partial. The conversion itself still walks the full selection.'
            });
        }

        if (selection.depth_limit_count > 0) {
            notes.push({ warn: true, text: 'Containers nested deeper than 64 levels are left alone.' });
        }

        return notes;
    }

    function na_pushNothingToConvertNote(notes, words) {
        var otherCount = na_otherScopePlan().convert_count || 0;
        var where = na_isDeep() ? 'anywhere in the selection' : 'at the current level of the selection';
        var text  = 'No ' + words.froms + ' to convert ' + where + '.';

        if (!na_isDeep() && otherCount > 0) {
            text += ' Deep Nesting would convert ' + na_countLabel(otherCount, words.from, words.froms) + '.';
        }

        notes.push({ warn: true, text: text });
    }

    function na_pushGroupsToComponentsNotes(notes, plan) {
        var definitionText = na_definitionSummaryText(plan);
        if (definitionText) { notes.push({ warn: false, text: definitionText }); }

        if (plan.common_preview_partial) {
            notes.push({
                warn: true,
                text: 'Common matching stopped early for this preview, so the __Common count may read low. ' +
                    'The conversion checks every group.'
            });
        }

        if (!naState.settings.merge_common_groups && (plan.convert_count || 0) > 1 && !plan.common_definition_count) {
            notes.push({
                warn: false,
                text: 'Turn on Common groups to give groups with the same geometry one shared component.'
            });
        }

        if (!na_isDeep()) { return; }

        if (plan.affected_definition_count > 0) {
            var outside = plan.outside_placement_count || 0;
            notes.push({
                warn: outside > 0,
                text: 'Nested groups convert inside ' +
                    na_countLabel(plan.affected_definition_count, 'component definition', 'component definitions') +
                    ', so every placement follows' +
                    (outside > 0
                        ? ', including ' + na_countLabel(outside, 'placement', 'placements') + ' outside the selection.'
                        : '.')
            });
        }

        if (plan.repeat_count > 0) {
            notes.push({
                warn: false,
                text: na_countLabel(plan.repeat_count, 'nested group repeats', 'nested groups repeat') +
                    ' inside shared definitions or merged copies, so they convert once rather than once per placement.'
            });
        }
    }

    function na_definitionSummaryText(plan) {
        var created = plan.new_definition_count || 0;
        if (!created) { return ''; }

        var common = plan.common_definition_count || 0;
        var single = plan.single_definition_count || 0;
        var lead   = 'Creates ' + na_countLabel(created, 'component definition', 'component definitions');

        if (!common) {
            return lead + (created === 1 ? ', named __Unique.' : ', each named __Unique.');
        }

        var text = lead + ': ' + na_formatNumber(common) + ' __Common, shared by ' +
            na_countLabel(plan.common_group_count, 'group', 'groups');
        if (single > 0) { text += ', and ' + na_formatNumber(single) + ' __Unique'; }
        return text + '.';
    }

    function na_pushComponentsToGroupsNotes(notes, plan) {
        if (plan.glue_or_cut_count > 0) {
            notes.push({
                warn: true,
                text: na_countLabel(plan.glue_or_cut_count, 'component glues to or cuts', 'components glue to or cut') +
                    ' faces. Groups cannot, so any openings they cut will close.'
            });
        }

        if (plan.other_placement_count > 0) {
            notes.push({
                warn: false,
                text: na_countLabel(plan.other_placement_count, 'other placement', 'other placements') +
                    ' of the selected components stay components.'
            });
        }

        if (plan.unique_definition_count > 0 && plan.convert_count > plan.unique_definition_count) {
            notes.push({
                warn: false,
                text: na_countLabel(plan.convert_count, 'placement', 'placements') + ' of ' +
                    na_countLabel(plan.unique_definition_count, 'definition', 'definitions') +
                    ' each get their own copy of the geometry, which grows the file.'
            });
        }

        if (plan.empty_skipped_count > 0) {
            notes.push({
                warn: false,
                text: na_countLabel(plan.empty_skipped_count, 'empty component is', 'empty components are') +
                    ' skipped; there is nothing to copy into a group.'
            });
        }
    }

    function na_selectionNotes() {
        var selection = naState.selection;
        if (!selection || !selection.has_selection) { return []; }

        var looseCount = (selection.selected_count || 0) -
            (selection.top_group_count || 0) - (selection.top_component_count || 0);
        if (looseCount <= 0) { return []; }

        return [{
            warn: false,
            text: na_countLabel(looseCount, 'loose entity', 'loose entities') +
                ' (faces, edges and so on) in the selection ' + na_pluralise(looseCount, 'is', 'are') + ' left alone.'
        }];
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Convert Button and Confirm Modal
    // -------------------------------------------------------------------------

    function na_canConvert() {
        var selection = naState.selection;
        return !!(selection && selection.has_selection && na_convertCount() > 0 && !naState.converting);
    }

    function na_updateConvertButton() {
        var button = na_el('naConverter_btnConvert');
        if (!button) { return; }

        var words = na_words();
        var count = na_convertCount();
        button.disabled = !na_canConvert();
        button.textContent = count > 0
            ? ('Convert ' + na_formatNumber(count) + ' ' + na_pluralise(count, words.From, words.Froms) +
               ' ' + NA_ARROW + ' ' + words.Tos + '...')
            : ('Convert ' + words.Froms + ' ' + NA_ARROW + ' ' + words.Tos + '...');
    }

    function na_openModal() {
        if (!na_canConvert()) { return; }

        var modal = na_el('naConverter_modal');
        var body  = na_el('naConverter_modalBody');
        if (!modal || !body) { return; }

        var words = na_words();
        var count = na_convertCount();
        na_setText('naConverter_modalTitle',
            'Convert ' + na_countLabel(count, words.from, words.froms) + ' to ' + words.tos + '?');
        body.innerHTML = na_modalBodyHtml();
        modal.classList.add('is-open');

        var confirmButton = na_el('naConverter_btnConfirm');
        if (confirmButton) { confirmButton.focus(); }
    }

    function na_closeModal() {
        var modal = na_el('naConverter_modal');
        if (modal) { modal.classList.remove('is-open'); }
    }

    function na_modalBodyHtml() {
        var plan  = na_currentPlan();
        var words = na_words();
        var lines = [];

        lines.push('<p>' + (na_isDeep()
            ? ('<strong>Deep Nesting:</strong> ' + na_formatNumber(plan.top_level_count) + ' at the current level and ' +
               na_formatNumber(plan.nested_count) + ' nested below it.')
            : ('<strong>Current Level Only:</strong> the selected ' + words.froms + ' only; nothing inside them changes.')) + '</p>');

        if (na_isGroupsToComponents()) {
            var definitionText = na_definitionSummaryText(plan);
            if (definitionText) { lines.push('<p>' + definitionText + '</p>'); }
            if (na_isDeep() && plan.outside_placement_count > 0) {
                lines.push('<p>Shared component definitions are edited, so ' +
                    na_countLabel(plan.outside_placement_count, 'placement', 'placements') +
                    ' outside the selection change too.</p>');
            }
        } else if (plan.glue_or_cut_count > 0) {
            lines.push('<p>' + na_countLabel(plan.glue_or_cut_count, 'component cuts or glues', 'components cut or glue') +
                ' to faces; as groups, any openings they cut will close.</p>');
        }

        if (plan.locked_skipped_count > 0 && !naState.settings.include_locked) {
            lines.push('<p>' + na_countLabel(plan.locked_skipped_count, 'locked container is', 'locked containers are') +
                ' skipped with everything inside.</p>');
        } else if (naState.settings.include_locked) {
            lines.push('<p>Locked containers are unlocked, converted and locked again.</p>');
        }

        lines.push('<p>Use SketchUp Undo to reverse the whole operation.</p>');
        return lines.join('');
    }

    function na_confirmConvert() {
        if (!na_canConvert()) {
            na_closeModal();
            return;
        }

        naState.converting = true;
        na_updateConvertButton();
        Na__GroupComponentConverter__ReceiveStatus('Converting...', 'info');
        na_closeModal();
        na_callRuby('na_convert', JSON.stringify(na_currentOptions()));
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Event Wiring
    // -------------------------------------------------------------------------

    function na_bindEvents() {
        na_bindClick('naConverter_btnRefresh', function () { na_callRuby('na_refresh'); });
        na_bindClick('naConverter_btnConvert', function () { na_openModal(); });
        na_bindClick('naConverter_btnCancel',  function () { na_closeModal(); });
        na_bindClick('naConverter_btnConfirm', function () { na_confirmConvert(); });

        var modalElement = na_el('naConverter_modal');
        if (modalElement) {
            modalElement.addEventListener('click', function (event) {
                if (event.target === modalElement) { na_closeModal(); }
            });
        }

        ['naConverter_dirGroupsToComponents', 'naConverter_dirComponentsToGroups',
         'naConverter_scopeCurrent', 'naConverter_scopeDeep',
         'naConverter_mergeCommon', 'naConverter_mergeCopies',
         'naConverter_includeLocked'].forEach(function (elementId) {
            var element = na_el(elementId);
            if (!element) { return; }
            element.addEventListener('change', na_handleControlChange);
        });

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') { na_closeModal(); }
        });
    }

    function na_bindClick(elementId, handler) {
        var element = na_el(elementId);
        if (element) { element.addEventListener('click', handler); }
    }

    function na_handleControlChange() {
        na_readControlsIntoState();
        na_renderAll();
        na_postOptions();
    }

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Ruby Facing Entry Points
    // -------------------------------------------------------------------------

    window.Na__GroupComponentConverter__ReceivePayload = function (payload) {
        naState.converting = false;
        if (!payload) { return; }

        na_renderSettings(payload.settings);
        naState.selection = payload.selection || null;
        na_renderAll();
    };

    window.Na__GroupComponentConverter__ReceiveSelection = function (selectionPayload) {
        naState.selection = selectionPayload || null;
        na_renderAll();
    };

    window.Na__GroupComponentConverter__ReceiveStatus = function (message, variant) {
        var statusElement = na_el('naConverter_status');
        if (!statusElement) { return; }

        statusElement.textContent = message;
        statusElement.className   = 'naConverter__StatusText' +
            (variant && variant !== 'info' ? ' naConverter__StatusText--' + variant : '');
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Boot
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function () {
        na_bindEvents();
        na_renderSettings(naState.settings);
        na_renderAll();
        na_log('Group / Component Converter dialog ready.');
        na_callRuby('na_dialog_ready');
    });

    // endregion ---------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
