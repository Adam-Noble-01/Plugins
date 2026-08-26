// =============================================================================
// NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - UI BRIDGE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__SceneDataTransfer__UiBridge__.js
// NAMESPACE  : window.Na__SceneTransfer__* (Ruby-facing entry points)
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Build the capture panel and the import scene list from the Ruby
//              payload, and round-trip every change back for persistence.
// CREATED    : 2026
//
// RUBY -> JS : Na__SceneTransfer__ReceivePayload(payload)
//              Na__SceneTransfer__ReceiveStatus(message, variant)
//              Na__SceneTransfer__ReceiveBusy(is_busy, label)
//              Na__SceneTransfer__ReceiveWarnings(warnings)
// JS -> RUBY : sketchup.na_dialog_ready  / na_refresh
//              sketchup.na_capture_model / na_clear_capture
//              sketchup.na_choose_source / na_read_source
//              sketchup.na_save_settings / na_import_scenes / na_js_log
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var naState = {
        domains         : [],                                                       // <-- Domain registry from Ruby
        scenes          : [],                                                       // <-- Source scene rows
        selectedScenes  : {},                                                       // <-- Scene name -> true
        captureDomains  : {},                                                       // <-- Domain key -> true, capture panel
        importDomains   : {},                                                       // <-- Domain key -> true, import panel
        nameSuffix      : '__IMPORTED',
        sourceLoaded    : false,
        sourcePath      : '',
        saveTimer       : null
    };

    var NA_SAVE_DEBOUNCE_MS = 250;

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Shorthand for getElementById
    // ------------------------------------------------------------
    function na_el(elementId) { return document.getElementById(elementId); }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Send a Log Line to the Ruby Console
    // ------------------------------------------------------------
    function na_log(message) {
        if (window.sketchup && window.sketchup.na_js_log) {
            window.sketchup.na_js_log(String(message));
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Create an Element With a Class and Optional Text
    // ------------------------------------------------------------
    function na_make(tagName, className, textContent) {
        var element = document.createElement(tagName);
        if (className)   { element.className   = className; }
        if (textContent !== undefined && textContent !== null) {
            element.textContent = textContent;
        }
        return element;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Count the Keys Flagged True in a Lookup Object
    // ------------------------------------------------------------
    function na_countTrue(lookupObject) {
        return Object.keys(lookupObject).filter(function (key) {
            return lookupObject[key] === true;
        }).length;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | List the Keys Flagged True in a Lookup Object
    // ------------------------------------------------------------
    function na_trueKeys(lookupObject) {
        return Object.keys(lookupObject).filter(function (key) {
            return lookupObject[key] === true;
        });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Tab Switching
    // -------------------------------------------------------------------------

    // FUNCTION | Activate One Tab and Its Panel
    // ------------------------------------------------------------
    function na_activateTab(tabElement) {
        var allTabs = document.querySelectorAll('.naSceneXfer__Tab');
        var i;

        for (i = 0; i < allTabs.length; i += 1) {
            allTabs[i].classList.remove('naSceneXfer__Tab--active');
            var panel = na_el(allTabs[i].getAttribute('data-panel'));
            if (panel) { panel.classList.remove('naSceneXfer__Panel--active'); }
        }

        tabElement.classList.add('naSceneXfer__Tab--active');
        var activePanel = na_el(tabElement.getAttribute('data-panel'));
        if (activePanel) { activePanel.classList.add('naSceneXfer__Panel--active'); }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Domain Toggle Rendering
    // -------------------------------------------------------------------------

    // FUNCTION | Build a Domain Toggle List Into a Container
    // ------------------------------------------------------------
    function na_renderDomainList(containerId, stateBucket, onChangeHandler) {
        var container = na_el(containerId);
        if (!container) { return; }

        container.innerHTML = '';

        naState.domains.forEach(function (domainRecord) {
            container.appendChild(na_buildDomainRow(domainRecord, stateBucket, onChangeHandler));
        });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Build a Single Domain Toggle Row
    // ------------------------------------------------------------
    function na_buildDomainRow(domainRecord, stateBucket, onChangeHandler) {
        var isLive  = domainRecord.implemented === true;
        var rowClass = 'naSceneXfer__DomainRow' + (isLive ? '' : ' naSceneXfer__DomainRow--disabled');
        var row     = na_make('label', rowClass);

        var checkbox   = document.createElement('input');
        checkbox.type  = 'checkbox';
        checkbox.checked = isLive && stateBucket[domainRecord.key] === true;
        checkbox.disabled = !isLive;

        checkbox.addEventListener('change', function () {
            stateBucket[domainRecord.key] = checkbox.checked;
            if (onChangeHandler) { onChangeHandler(); }
        });

        var textWrap = na_make('span', 'naSceneXfer__DomainText');
        var label    = na_make('span', 'naSceneXfer__DomainLabel', domainRecord.label);

        if (!isLive) {
            label.appendChild(na_make('span', 'naSceneXfer__DomainBadge', 'Phase 2'));
        }

        textWrap.appendChild(label);
        textWrap.appendChild(na_make('span', 'naSceneXfer__DomainSummary', domainRecord.summary));

        // Style and Fog are one SketchUp scene property (use_rendering_options),
        // so ticking either enables it. Say so rather than implying otherwise.
        if (domainRecord.shares_flag) {
            textWrap.appendChild(na_make('span', 'naSceneXfer__DomainShared', domainRecord.shares_flag));
        }

        row.appendChild(checkbox);
        row.appendChild(textWrap);
        return row;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Scene List Rendering
    // -------------------------------------------------------------------------

    // FUNCTION | Rebuild the Source Scene Tick List
    // ------------------------------------------------------------
    function na_renderSceneList() {
        var listElement = na_el('naSceneXfer_sceneList');
        listElement.innerHTML = '';

        if (!naState.sourceLoaded) {
            listElement.appendChild(na_make(
                'div', 'naSceneXfer__EmptyState',
                'No source model read yet. Press Browse to pick a .skp that has had its scenes captured.'
            ));
            na_updateSelectionCount();
            return;
        }

        if (!naState.scenes.length) {
            listElement.appendChild(na_make(
                'div', 'naSceneXfer__EmptyState',
                'The source model carries captured data, but it contains no scenes.'
            ));
            na_updateSelectionCount();
            return;
        }

        naState.scenes.forEach(function (sceneRecord) {
            listElement.appendChild(na_buildSceneRow(sceneRecord));
        });

        na_applySceneFilter();
        na_updateSelectionCount();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Build a Single Scene Row
    // ------------------------------------------------------------
    function na_buildSceneRow(sceneRecord) {
        var row = na_make('label', 'naSceneXfer__SceneRow');
        row.setAttribute('data-scene-name', sceneRecord.name);

        var checkbox     = document.createElement('input');
        checkbox.type    = 'checkbox';
        checkbox.checked = naState.selectedScenes[sceneRecord.name] === true;

        checkbox.addEventListener('change', function () {
            naState.selectedScenes[sceneRecord.name] = checkbox.checked;
            na_updateSelectionCount();
            na_queueSave();
        });

        var body = na_make('div', 'naSceneXfer__SceneBody');
        body.appendChild(na_make('div', 'naSceneXfer__SceneName', sceneRecord.name));

        var metaParts = [];
        if (sceneRecord.description) { metaParts.push(sceneRecord.description); }
        if (sceneRecord.available && sceneRecord.available.length) {
            metaParts.push('captured: ' + sceneRecord.available.join(', '));
        }
        body.appendChild(na_make('div', 'naSceneXfer__SceneMeta', metaParts.join('  |  ')));

        row.appendChild(na_make('span', 'naSceneXfer__SceneIndex', String(sceneRecord.index + 1)));
        row.appendChild(checkbox);
        row.appendChild(body);

        if (sceneRecord.is_two_point) {
            row.appendChild(na_make('span', 'naSceneXfer__SceneFlag', '2-point'));
        } else if (sceneRecord.camera_is_active === false) {
            row.appendChild(na_make('span', 'naSceneXfer__SceneFlag', 'no camera'));
        }

        return row;
    }
    // ------------------------------------------------------------

    // FUNCTION | Hide Scene Rows That Do Not Match the Filter Text
    // ------------------------------------------------------------
    function na_applySceneFilter() {
        var filterInput = na_el('naSceneXfer_sceneFilter');
        var filterText  = filterInput ? filterInput.value.trim().toLowerCase() : '';
        var rows        = document.querySelectorAll('.naSceneXfer__SceneRow');
        var i;

        for (i = 0; i < rows.length; i += 1) {
            var sceneName = (rows[i].getAttribute('data-scene-name') || '').toLowerCase();
            var isMatch   = !filterText || sceneName.indexOf(filterText) !== -1;
            rows[i].classList.toggle('naSceneXfer__SceneRow--hidden', !isMatch);
        }
    }
    // ------------------------------------------------------------

    // FUNCTION | Update the Ticked Count and the Import Button State
    // ------------------------------------------------------------
    function na_updateSelectionCount() {
        var tickedCount  = na_countTrue(naState.selectedScenes);
        var totalCount   = naState.scenes.length;
        var domainCount  = na_countTrue(naState.importDomains);
        var countElement = na_el('naSceneXfer_selectionCount');

        if (countElement) {
            countElement.textContent = tickedCount + ' of ' + totalCount + ' ticked';
        }

        var canImport = naState.sourceLoaded && tickedCount > 0 && domainCount > 0;
        var button    = na_el('naSceneXfer_btnImport');
        if (button) { button.disabled = !canImport; }

        var hint = na_el('naSceneXfer_importHint');
        if (hint) {
            if (!naState.sourceLoaded)   { hint.textContent = 'Read a source model first.'; }
            else if (tickedCount === 0)  { hint.textContent = 'Tick at least one scene.'; }
            else if (domainCount === 0)  { hint.textContent = 'Tick at least one thing to reconstruct.'; }
            else {
                hint.textContent = 'Will create ' + tickedCount +
                    (tickedCount === 1 ? ' scene' : ' scenes') + ' carrying ' +
                    na_trueKeys(naState.importDomains).join(', ') + '.';
            }
        }

        na_updateNamePreview();
    }
    // ------------------------------------------------------------

    // FUNCTION | Show What an Imported Scene Will Be Called
    // ------------------------------------------------------------
    function na_updateNamePreview() {
        var preview = na_el('naSceneXfer_namePreview');
        if (!preview) { return; }

        var sample = naState.scenes.length ? naState.scenes[0].name : 'Scene 1';
        preview.textContent = 'Example: ' + sample + naState.nameSuffix;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Card Rendering
    // -------------------------------------------------------------------------

    // FUNCTION | Render the Embedded Capture Summary for This Model
    // ------------------------------------------------------------
    function na_renderCaptureState(localCapture) {
        var card = na_el('naSceneXfer_captureState');
        card.innerHTML = '';

        if (!localCapture || !localCapture.chunk_count) {
            card.appendChild(na_make(
                'div', 'naSceneXfer__StateEmpty',
                'No scene data captured in this model yet.'
            ));
            return;
        }

        var grid = na_make('div', 'naSceneXfer__StateGrid');
        na_addStateRow(grid, 'Captured',        localCapture.captured_at || '-');
        na_addStateRow(grid, 'Scenes',          String(localCapture.scene_count || 0));
        na_addStateRow(grid, 'Includes',        (localCapture.domains_captured || []).join(', ') || '-');
        na_addStateRow(grid, 'Payload size',    na_formatBytes(localCapture.byte_length));
        na_addStateRow(grid, 'Storage',         localCapture.chunk_count + ' chunk(s), ' + (localCapture.encoding || 'raw'));
        na_addStateRow(grid, 'Schema',          localCapture.schema_version || '-');
        card.appendChild(grid);
    }
    // ------------------------------------------------------------

    // FUNCTION | Render the Source Model Summary Card
    // ------------------------------------------------------------
    function na_renderSourceCard(sourceBlock) {
        var card = na_el('naSceneXfer_sourceCard');
        card.innerHTML = '';

        if (!sourceBlock || !sourceBlock.loaded) {
            var empty = na_make('div', 'naSceneXfer__StateEmpty');
            empty.innerHTML = 'Pick a <code>.skp</code> that has already had its scenes captured. It is read ' +
                              'directly from disk &mdash; the file is never opened and your current model is ' +
                              'never disturbed.';
            card.appendChild(empty);
            return;
        }

        var header = sourceBlock.header || {};
        var grid   = na_make('div', 'naSceneXfer__StateGrid');
        na_addStateRow(grid, 'Source model',  header.source_model_name || '-');
        na_addStateRow(grid, 'Captured',      header.captured_at || '-');
        na_addStateRow(grid, 'Scenes found',  String(header.scene_count || 0));
        na_addStateRow(grid, 'Includes',      (header.domains_captured || []).join(', ') || '-');
        na_addStateRow(grid, 'Saved with',    'SketchUp ' + (header.sketchup_version || '-'));
        na_addStateRow(grid, 'Schema',        header.schema_version || '-');
        card.appendChild(grid);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Append a Key and Value Pair to a State Grid
    // ------------------------------------------------------------
    function na_addStateRow(gridElement, keyText, valueText) {
        gridElement.appendChild(na_make('div', 'naSceneXfer__StateKey',   keyText));
        gridElement.appendChild(na_make('div', 'naSceneXfer__StateValue', valueText));
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Format a Byte Count for Display
    // ------------------------------------------------------------
    function na_formatBytes(byteLength) {
        var bytes = Number(byteLength) || 0;
        if (bytes < 1024)        { return bytes + ' B'; }
        if (bytes < 1024 * 1024) { return (bytes / 1024).toFixed(1) + ' KB'; }
        return (bytes / (1024 * 1024)).toFixed(2) + ' MB';
    }
    // ------------------------------------------------------------

    // FUNCTION | Render the Warning List From the Last Import
    // ------------------------------------------------------------
    function na_renderWarnings(warnings) {
        var group = na_el('naSceneXfer_warningsGroup');
        var list  = na_el('naSceneXfer_warningList');
        list.innerHTML = '';

        if (!warnings || !warnings.length) {
            group.classList.add('naSceneXfer__Group--hidden');
            return;
        }

        warnings.forEach(function (warningText) {
            list.appendChild(na_make('div', 'naSceneXfer__WarningItem', warningText));
        });

        group.classList.remove('naSceneXfer__Group--hidden');
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Persistence
    // -------------------------------------------------------------------------

    // FUNCTION | Queue a Debounced Settings Save Back to Ruby
    // ------------------------------------------------------------
    function na_queueSave() {
        if (naState.saveTimer) { window.clearTimeout(naState.saveTimer); }
        naState.saveTimer = window.setTimeout(na_saveSettings, NA_SAVE_DEBOUNCE_MS);
    }
    // ------------------------------------------------------------

    // FUNCTION | Push the Current Dialog Settings to Ruby
    // ------------------------------------------------------------
    function na_saveSettings() {
        if (!window.sketchup || !window.sketchup.na_save_settings) { return; }

        window.sketchup.na_save_settings(JSON.stringify({
            source_model_path : naState.sourcePath,
            name_suffix       : naState.nameSuffix,
            selected_domains  : na_trueKeys(naState.importDomains),
            selected_scenes   : na_trueKeys(naState.selectedScenes)
        }));
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Event Wiring
    // -------------------------------------------------------------------------

    // FUNCTION | Bind Every Control Once at Startup
    // ------------------------------------------------------------
    function na_bindEvents() {
        na_el('naSceneXfer_tabCapture').addEventListener('click', function () { na_activateTab(this); });
        na_el('naSceneXfer_tabImport').addEventListener('click',  function () { na_activateTab(this); });

        na_el('naSceneXfer_btnRefresh').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_refresh) { window.sketchup.na_refresh(); }
        });

        na_el('naSceneXfer_btnCapture').addEventListener('click', function () {
            if (!window.sketchup || !window.sketchup.na_capture_model) { return; }
            window.sketchup.na_capture_model(JSON.stringify({ domains: na_trueKeys(naState.captureDomains) }));
        });

        na_el('naSceneXfer_btnClearCapture').addEventListener('click', function () {
            if (!window.sketchup || !window.sketchup.na_clear_capture) { return; }
            if (!window.confirm('Remove the captured scene data from this model?')) { return; }
            window.sketchup.na_clear_capture();
        });

        na_el('naSceneXfer_btnBrowse').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_choose_source) { window.sketchup.na_choose_source(); }
        });

        na_el('naSceneXfer_btnReread').addEventListener('click', function () {
            if (!window.sketchup || !window.sketchup.na_read_source) { return; }
            window.sketchup.na_read_source(naState.sourcePath);
        });

        na_el('naSceneXfer_btnAllOn').addEventListener('click',  function () { na_setAllScenes(true); });
        na_el('naSceneXfer_btnAllOff').addEventListener('click', function () { na_setAllScenes(false); });
        na_el('naSceneXfer_btnInvert').addEventListener('click', na_invertScenes);

        na_el('naSceneXfer_btnDomAll').addEventListener('click',  function () { na_setAllImportDomains(true); });
        na_el('naSceneXfer_btnDomNone').addEventListener('click', function () { na_setAllImportDomains(false); });

        na_el('naSceneXfer_sceneFilter').addEventListener('input', na_applySceneFilter);

        na_el('naSceneXfer_suffix').addEventListener('input', function () {
            naState.nameSuffix = this.value;
            na_updateNamePreview();
            na_queueSave();
        });

        na_el('naSceneXfer_btnImport').addEventListener('click', na_startImport);
    }
    // ------------------------------------------------------------

    // FUNCTION | Tick or Untick Every Visible Scene
    // ------------------------------------------------------------
    function na_setAllScenes(isSelected) {
        var rows = document.querySelectorAll('.naSceneXfer__SceneRow:not(.naSceneXfer__SceneRow--hidden)');
        var i;

        for (i = 0; i < rows.length; i += 1) {
            var sceneName = rows[i].getAttribute('data-scene-name');
            var checkbox  = rows[i].querySelector('input[type="checkbox"]');
            naState.selectedScenes[sceneName] = isSelected;
            if (checkbox) { checkbox.checked = isSelected; }
        }

        na_updateSelectionCount();
        na_queueSave();
    }
    // ------------------------------------------------------------

    // FUNCTION | Invert the Tick State of Every Visible Scene
    // ------------------------------------------------------------
    function na_invertScenes() {
        var rows = document.querySelectorAll('.naSceneXfer__SceneRow:not(.naSceneXfer__SceneRow--hidden)');
        var i;

        for (i = 0; i < rows.length; i += 1) {
            var sceneName = rows[i].getAttribute('data-scene-name');
            var checkbox  = rows[i].querySelector('input[type="checkbox"]');
            var nextValue = !(naState.selectedScenes[sceneName] === true);
            naState.selectedScenes[sceneName] = nextValue;
            if (checkbox) { checkbox.checked = nextValue; }
        }

        na_updateSelectionCount();
        na_queueSave();
    }
    // ------------------------------------------------------------

    // FUNCTION | Tick or Untick Every Implemented Import Domain
    // ------------------------------------------------------------
    function na_setAllImportDomains(isSelected) {
        naState.domains.forEach(function (domainRecord) {
            if (domainRecord.implemented !== true) { return; }
            naState.importDomains[domainRecord.key] = isSelected;
        });

        na_renderDomainList('naSceneXfer_importDomains', naState.importDomains, function () {
            na_updateSelectionCount();
            na_queueSave();
        });

        na_updateSelectionCount();
        na_queueSave();
    }
    // ------------------------------------------------------------

    // FUNCTION | Send the Import Request to Ruby
    // ------------------------------------------------------------
    function na_startImport() {
        if (!window.sketchup || !window.sketchup.na_import_scenes) { return; }

        window.sketchup.na_import_scenes(JSON.stringify({
            scene_names : na_trueKeys(naState.selectedScenes),
            domains     : na_trueKeys(naState.importDomains),
            name_suffix : naState.nameSuffix
        }));
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Ruby To JavaScript Entry Points
    // -------------------------------------------------------------------------

    // FUNCTION | Receive the Full State Payload From Ruby
    // ------------------------------------------------------------
    window.Na__SceneTransfer__ReceivePayload = function (payload) {
        try {
            var choices  = payload.choices  || {};
            var settings = payload.settings || {};
            var source   = payload.source   || {};

            naState.domains      = choices.domains || [];
            naState.nameSuffix   = settings.name_suffix || choices.default_suffix || '__IMPORTED';
            naState.sourcePath   = source.path || settings.source_model_path || '';
            naState.sourceLoaded = source.loaded === true;
            naState.scenes       = source.scenes || [];

            na_seedDomainState(settings.selected_domains || []);
            na_seedSceneState(settings.selected_scenes || []);

            na_renderModelMeta(payload.model || {});
            na_renderCaptureState(payload.local_capture);
            na_renderSourceCard(source);

            na_el('naSceneXfer_sourcePath').value = naState.sourcePath;
            na_el('naSceneXfer_suffix').value     = naState.nameSuffix;

            na_renderDomainList('naSceneXfer_captureDomains', naState.captureDomains, null);
            na_renderDomainList('naSceneXfer_importDomains',  naState.importDomains, function () {
                na_updateSelectionCount();
                na_queueSave();
            });

            na_renderSceneList();
            na_renderCaptureHint(payload.local_capture, settings.last_capture);
        } catch (error) {
            na_log('ReceivePayload error: ' + error.message);
        }
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive a Status Bar Message From Ruby
    // ------------------------------------------------------------
    window.Na__SceneTransfer__ReceiveStatus = function (message, variant) {
        var statusElement = na_el('naSceneXfer_status');
        if (!statusElement) { return; }

        statusElement.textContent = message;
        statusElement.className   = 'naSceneXfer__StatusText' +
            (variant ? ' naSceneXfer__StatusText--' + variant : '');
    };
    // ------------------------------------------------------------

    // FUNCTION | Show or Hide the Busy Overlay
    // ------------------------------------------------------------
    window.Na__SceneTransfer__ReceiveBusy = function (isBusy, labelText) {
        var overlay = na_el('naSceneXfer_busy');
        var label   = na_el('naSceneXfer_busyLabel');

        if (label && labelText) { label.textContent = labelText; }
        if (overlay) { overlay.classList.toggle('naSceneXfer__Busy--active', isBusy === true); }
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive Import Warnings From Ruby
    // ------------------------------------------------------------
    window.Na__SceneTransfer__ReceiveWarnings = function (warnings) {
        na_renderWarnings(warnings);
    };
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | State Seeding
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Seed the Domain Tick State From Persisted Settings
    // ------------------------------------------------------------
    // Capture always defaults to everything implemented, because a partial
    // capture is rarely what anyone wants. Import honours the saved selection.
    function na_seedDomainState(savedDomains) {
        naState.captureDomains = {};
        naState.importDomains  = {};

        naState.domains.forEach(function (domainRecord) {
            if (domainRecord.implemented !== true) { return; }

            naState.captureDomains[domainRecord.key] = true;
            naState.importDomains[domainRecord.key]  =
                savedDomains.length ? savedDomains.indexOf(domainRecord.key) !== -1 : true;
        });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Seed the Scene Tick State, Dropping Names That Have Gone
    // ------------------------------------------------------------
    function na_seedSceneState(savedScenes) {
        var liveNames = {};
        naState.scenes.forEach(function (sceneRecord) { liveNames[sceneRecord.name] = true; });

        naState.selectedScenes = {};
        savedScenes.forEach(function (sceneName) {
            if (liveNames[sceneName]) { naState.selectedScenes[sceneName] = true; }
        });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Render the Toolbar Model Summary
    // ------------------------------------------------------------
    function na_renderModelMeta(modelInfo) {
        var metaElement = na_el('naSceneXfer_modelMeta');
        if (!metaElement) { return; }

        var sceneCount = modelInfo.scene_count || 0;
        metaElement.textContent = (modelInfo.name || 'Untitled') + '  |  ' +
            sceneCount + (sceneCount === 1 ? ' scene' : ' scenes') +
            (modelInfo.is_saved ? '' : '  |  not saved yet');
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Render the Capture Action Hint
    // ------------------------------------------------------------
    function na_renderCaptureHint(localCapture, lastCapture) {
        var hint = na_el('naSceneXfer_captureHint');
        if (!hint) { return; }

        if (localCapture && localCapture.chunk_count) {
            hint.textContent = 'Re-capturing replaces the existing data. Remember to save.';
        } else if (lastCapture && lastCapture.time) {
            hint.textContent = 'Last captured ' + lastCapture.time + '.';
        } else {
            hint.textContent = 'Captures every scene in this model.';
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Bootstrap
    // -------------------------------------------------------------------------

    // FUNCTION | Wire Up and Ask Ruby for the First Payload
    // ------------------------------------------------------------
    function na_boot() {
        na_bindEvents();

        if (window.sketchup && window.sketchup.na_dialog_ready) {
            window.sketchup.na_dialog_ready();
        }
    }
    // ------------------------------------------------------------

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', na_boot);
    } else {
        na_boot();
    }

    // endregion ---------------------------------------------------------------

}());

// =============================================================================
// END OF FILE
// =============================================================================
