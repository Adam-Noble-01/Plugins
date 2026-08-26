// =============================================================================
// NA NOBLE3D MODELLING TOOLS - SCENE IMAGE EXPORTER - UI BRIDGE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__SceneImageExporter__UiBridge__.js
// NAMESPACE  : window.Na__SceneExporter__* (Ruby-facing entry points)
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Build the scene tick list and settings form from the Ruby
//              payload, and round-trip every change back for persistence.
// CREATED    : 2026
//
// RUBY -> JS : Na__SceneExporter__ReceivePayload(payload)
//              Na__SceneExporter__ReceiveProgress(status)
//              Na__SceneExporter__ReceiveStatus(message, variant)
//              Na__SceneExporter__ReceiveResolved(resolved)
//              Na__SceneExporter__ReceiveFolder(folder)
// JS -> RUBY : sketchup.na_dialog_ready / na_refresh_scenes / na_save_selection
//              sketchup.na_save_settings / na_choose_folder / na_open_folder
//              sketchup.na_start_export / na_cancel_export / na_js_log
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var naState = {
        choices        : null,                                                      // <-- Preset / size / aspect lists from Ruby
        settings       : null,                                                      // <-- Live settings hash
        scenes         : [],                                                        // <-- Scene rows from the model
        selectedNames  : {},                                                        // <-- Name -> true for every ticked scene
        modelInfo      : null,
        isRunning      : false,
        suppressChange : false,                                                     // <-- True while a preset is being applied
        saveTimer      : null
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

    // HELPER FUNCTION | Toggle the Hidden Modifier on a Field Container
    // ------------------------------------------------------------
    function na_setFieldVisible(elementId, isVisible) {
        var element = na_el(elementId);
        if (!element) { return; }

        if (isVisible) {
            element.classList.remove('naSceneExp__Field--hidden');
        } else {
            element.classList.add('naSceneExp__Field--hidden');
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Fill a Select Element From a List of Option Records
    // ------------------------------------------------------------
    function na_fillSelect(selectId, records, valueField, labelField) {
        var selectElement = na_el(selectId);
        if (!selectElement) { return; }

        selectElement.innerHTML = '';
        records.forEach(function (record) {
            var optionElement = document.createElement('option');
            optionElement.value       = String(record[valueField]);
            optionElement.textContent = record[labelField];
            selectElement.appendChild(optionElement);
        });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Scene List Rendering
    // -------------------------------------------------------------------------

    // FUNCTION | Rebuild the Scene Tick List From the Current State
    // ------------------------------------------------------------
    function na_renderSceneList() {
        var listElement = na_el('naSceneExp_sceneList');
        listElement.innerHTML = '';

        if (!naState.scenes.length) {
            var emptyElement = document.createElement('div');
            emptyElement.className   = 'naSceneExp__EmptyState';
            emptyElement.textContent = 'This model has no scenes. Add scene tabs in SketchUp, then press Refresh Scenes.';
            listElement.appendChild(emptyElement);
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

    // HELPER FUNCTION | Build One Scene Row Element
    // ------------------------------------------------------------
    function na_buildSceneRow(sceneRecord) {
        var isTicked = !!naState.selectedNames[sceneRecord.name];

        var rowElement = document.createElement('label');
        rowElement.className = 'naSceneExp__SceneRow' + (isTicked ? ' naSceneExp__SceneRow--selected' : '');
        rowElement.setAttribute('data-scene-name', sceneRecord.name);

        var checkElement  = document.createElement('input');
        checkElement.type      = 'checkbox';
        checkElement.className = 'naSceneExp__SceneCheck';
        checkElement.checked   = isTicked;
        checkElement.addEventListener('change', function () {
            na_setSceneTicked(sceneRecord.name, checkElement.checked);
        });

        var indexElement = document.createElement('span');
        indexElement.className   = 'naSceneExp__SceneIndex';
        indexElement.textContent = na_padNumber(sceneRecord.index + 1);

        var bodyElement = document.createElement('span');
        bodyElement.className = 'naSceneExp__SceneBody';

        var nameElement = document.createElement('span');
        nameElement.className   = 'naSceneExp__SceneName';
        nameElement.textContent = sceneRecord.name;
        bodyElement.appendChild(nameElement);

        if (sceneRecord.description) {
            var descElement = document.createElement('span');
            descElement.className   = 'naSceneExp__SceneDesc';
            descElement.textContent = sceneRecord.description;
            bodyElement.appendChild(descElement);
        }

        rowElement.appendChild(checkElement);
        rowElement.appendChild(indexElement);
        rowElement.appendChild(bodyElement);
        return rowElement;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Pad a Row Number to Two Digits
    // ------------------------------------------------------------
    function na_padNumber(value) {
        return (value < 10 ? '0' : '') + String(value);
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Hide Rows That Do Not Match the Filter Text
    // ------------------------------------------------------------
    function na_applySceneFilter() {
        var filterText = na_el('naSceneExp_sceneFilter').value.toLowerCase().trim();
        var rowElements = document.querySelectorAll('.naSceneExp__SceneRow');

        for (var rowIndex = 0; rowIndex < rowElements.length; rowIndex += 1) {
            var rowElement = rowElements[rowIndex];
            var sceneName  = (rowElement.getAttribute('data-scene-name') || '').toLowerCase();
            var isMatch    = !filterText || sceneName.indexOf(filterText) !== -1;

            if (isMatch) {
                rowElement.classList.remove('naSceneExp__SceneRow--hidden');
            } else {
                rowElement.classList.add('naSceneExp__SceneRow--hidden');
            }
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Scene Selection State
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Tick or Untick One Scene and Persist the Change
    // ------------------------------------------------------------
    function na_setSceneTicked(sceneName, isTicked) {
        if (isTicked) {
            naState.selectedNames[sceneName] = true;
        } else {
            delete naState.selectedNames[sceneName];
        }

        na_syncRowHighlight(sceneName, isTicked);
        na_updateSelectionCount();
        na_saveSelection();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Apply a Tick State to Every Visible Scene Row
    // ------------------------------------------------------------
    function na_setAllTicked(mode) {
        var rowElements = document.querySelectorAll('.naSceneExp__SceneRow');

        for (var rowIndex = 0; rowIndex < rowElements.length; rowIndex += 1) {
            var rowElement = rowElements[rowIndex];
            if (rowElement.classList.contains('naSceneExp__SceneRow--hidden')) { continue; }

            var sceneName    = rowElement.getAttribute('data-scene-name');
            var checkElement = rowElement.querySelector('input[type="checkbox"]');
            var nextState;

            if (mode === 'on')       { nextState = true; }
            else if (mode === 'off') { nextState = false; }
            else                     { nextState = !checkElement.checked; }

            checkElement.checked = nextState;
            if (nextState) {
                naState.selectedNames[sceneName] = true;
            } else {
                delete naState.selectedNames[sceneName];
            }
            na_syncRowHighlight(sceneName, nextState);
        }

        na_updateSelectionCount();
        na_saveSelection();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Keep the Row Highlight in Step With the Checkbox
    // ------------------------------------------------------------
    function na_syncRowHighlight(sceneName, isTicked) {
        var rowElements = document.querySelectorAll('.naSceneExp__SceneRow');

        for (var rowIndex = 0; rowIndex < rowElements.length; rowIndex += 1) {
            if (rowElements[rowIndex].getAttribute('data-scene-name') !== sceneName) { continue; }

            if (isTicked) {
                rowElements[rowIndex].classList.add('naSceneExp__SceneRow--selected');
            } else {
                rowElements[rowIndex].classList.remove('naSceneExp__SceneRow--selected');
            }
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Collect the Ticked Scene Names in Model Scene Order
    // ------------------------------------------------------------
    function na_tickedSceneNames() {
        return naState.scenes
            .filter(function (sceneRecord) { return !!naState.selectedNames[sceneRecord.name]; })
            .map(function (sceneRecord) { return sceneRecord.name; });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Refresh the "n of m ticked" Counter and Export Button
    // ------------------------------------------------------------
    function na_updateSelectionCount() {
        var tickedCount = na_tickedSceneNames().length;
        na_el('naSceneExp_selectionCount').textContent =
            tickedCount + ' of ' + naState.scenes.length + ' ticked';
        na_updateExportButtonState();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Push the Ticked Scene Names to Ruby for Persistence
    // ------------------------------------------------------------
    function na_saveSelection() {
        if (!window.sketchup || !window.sketchup.na_save_selection) { return; }

        window.sketchup.na_save_selection(JSON.stringify({ scene_names: na_tickedSceneNames() }));
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Settings Form - Population
    // -------------------------------------------------------------------------

    // FUNCTION | Fill Every Dropdown From the Ruby Choice Lists
    // ------------------------------------------------------------
    function na_buildChoiceLists() {
        var choices = naState.choices;

        na_fillSelect('naSceneExp_preset',        choices.presets,         'key',   'label');
        na_fillSelect('naSceneExp_aspectMode',    choices.aspect_modes,    'key',   'label');
        na_fillSelect('naSceneExp_fileFormat',    choices.file_formats,    'key',   'label');
        na_fillSelect('naSceneExp_overwriteMode', choices.overwrite_modes, 'key',   'label');

        var heightRecords = choices.height_steps.map(function (record) {
            return { value: record.value, label: record.label };
        });
        heightRecords.push({ value: '', label: 'Custom height (set below)' });
        na_fillSelect('naSceneExp_heightStep', heightRecords, 'value', 'label');

        na_buildOverrideRows();
        na_buildTokenChips();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Build One Tri-State Row per Render Override
    // ------------------------------------------------------------
    function na_buildOverrideRows() {
        var containerElement = na_el('naSceneExp_overrideList');
        containerElement.innerHTML = '';

        naState.choices.render_overrides.forEach(function (overrideRecord) {
            var rowElement = document.createElement('div');
            rowElement.className = 'naSceneExp__OverrideRow';

            var labelElement = document.createElement('span');
            labelElement.className   = 'naSceneExp__OverrideLabel';
            labelElement.textContent = overrideRecord.label;
            labelElement.title       = overrideRecord.hint;

            var selectElement = document.createElement('select');
            selectElement.className = 'naSceneExp__OverrideSelect';
            selectElement.setAttribute('data-override-key', overrideRecord.key);

            naState.choices.override_states.forEach(function (stateRecord) {
                var optionElement = document.createElement('option');
                optionElement.value       = stateRecord.key;
                optionElement.textContent = stateRecord.label;
                selectElement.appendChild(optionElement);
            });

            selectElement.addEventListener('change', function () {
                naState.settings.render_overrides[overrideRecord.key] = selectElement.value;
                na_markCustomPreset();
                na_syncConditionalFields();
                na_saveSettings();
            });

            rowElement.appendChild(labelElement);
            rowElement.appendChild(selectElement);
            containerElement.appendChild(rowElement);
        });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Build the Clickable Filename Token Chips
    // ------------------------------------------------------------
    function na_buildTokenChips() {
        var containerElement = na_el('naSceneExp_tokenRow');
        containerElement.innerHTML = '';

        naState.choices.filename_tokens.forEach(function (tokenRecord) {
            var chipElement = document.createElement('span');
            chipElement.className   = 'naSceneExp__Token';
            chipElement.textContent = tokenRecord.token;
            chipElement.title       = tokenRecord.hint + '  (click to insert)';
            chipElement.addEventListener('click', function () {
                na_insertToken(tokenRecord.token);
            });
            containerElement.appendChild(chipElement);
        });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Insert a Token at the Caret in the Filename Pattern Field
    // ------------------------------------------------------------
    function na_insertToken(tokenText) {
        var inputElement = na_el('naSceneExp_filenamePattern');
        var caretStart   = inputElement.selectionStart;
        var caretEnd     = inputElement.selectionEnd;
        var currentValue = inputElement.value;

        if (caretStart === null || caretStart === undefined) {
            inputElement.value = currentValue + tokenText;
        } else {
            inputElement.value = currentValue.slice(0, caretStart) + tokenText + currentValue.slice(caretEnd);
            inputElement.selectionStart = inputElement.selectionEnd = caretStart + tokenText.length;
        }

        inputElement.focus();
        naState.settings.filename_pattern = inputElement.value;
        na_saveSettings();
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Settings Form - Read and Write
    // -------------------------------------------------------------------------

    // FUNCTION | Write the Settings Hash Into the Form Controls
    // ------------------------------------------------------------
    function na_applySettingsToForm() {
        var settings = naState.settings;
        naState.suppressChange = true;

        na_el('naSceneExp_preset').value           = settings.preset_key;
        na_el('naSceneExp_heightCustom').value     = settings.image_height;
        na_el('naSceneExp_heightStep').value       = na_matchingHeightStep(settings.image_height);
        na_el('naSceneExp_aspectMode').value       = settings.aspect_mode;
        na_el('naSceneExp_aspectW').value          = settings.custom_aspect_width;
        na_el('naSceneExp_aspectH').value          = settings.custom_aspect_height;
        na_el('naSceneExp_fileFormat').value       = settings.file_format;
        na_el('naSceneExp_jpegQuality').value      = settings.jpeg_quality;
        na_el('naSceneExp_jpegQualityValue').textContent = Number(settings.jpeg_quality).toFixed(2);
        na_el('naSceneExp_lineScale').value        = settings.line_scale_factor;
        na_el('naSceneExp_lineScaleValue').textContent   = Number(settings.line_scale_factor).toFixed(1) + 'x';
        na_el('naSceneExp_transparent').checked    = !!settings.transparent_background;
        na_el('naSceneExp_filenamePattern').value  = settings.filename_pattern;
        na_el('naSceneExp_overwriteMode').value    = settings.overwrite_mode;
        na_el('naSceneExp_folderPath').value       = settings.export_folder || '';
        na_el('naSceneExp_silhouetteWidth').value  = settings.silhouette_width;
        na_el('naSceneExp_lineExtension').value    = settings.line_extension_amount;

        var overrideSelects = document.querySelectorAll('.naSceneExp__OverrideSelect');
        for (var selectIndex = 0; selectIndex < overrideSelects.length; selectIndex += 1) {
            var overrideKey = overrideSelects[selectIndex].getAttribute('data-override-key');
            overrideSelects[selectIndex].value = settings.render_overrides[overrideKey] || 'scene';
        }

        naState.suppressChange = false;

        na_syncConditionalFields();
        na_updatePresetHint();
        na_updateExportButtonState();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Find the Height Step Matching the Current Height
    // ------------------------------------------------------------
    function na_matchingHeightStep(heightValue) {
        var matched = naState.choices.height_steps.filter(function (record) {
            return Number(record.value) === Number(heightValue);
        });
        return matched.length ? String(matched[0].value) : '';
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Show or Hide the Conditional Rows
    // ------------------------------------------------------------
    function na_syncConditionalFields() {
        var settings = naState.settings;

        na_setFieldVisible('naSceneExp_customAspectRow', settings.aspect_mode === 'custom');
        na_setFieldVisible('naSceneExp_jpegRow',         settings.file_format === 'jpg');
        na_setFieldVisible('naSceneExp_silhouetteRow',   settings.render_overrides.profiles === 'on');
        na_setFieldVisible('naSceneExp_extensionRow',    settings.render_overrides.edge_extensions === 'on');

        var transparentInput = na_el('naSceneExp_transparent');
        transparentInput.disabled = settings.file_format !== 'png';
        na_el('naSceneExp_transparentRow').style.opacity = transparentInput.disabled ? '0.5' : '1';
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Show the Hint Line for the Active Preset
    // ------------------------------------------------------------
    function na_updatePresetHint() {
        var activeKey = naState.settings.preset_key;
        var matched   = naState.choices.presets.filter(function (record) { return record.key === activeKey; });
        na_el('naSceneExp_presetHint').textContent = matched.length ? matched[0].hint : '';
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Flip the Preset Selector to Custom After a Manual Edit
    // ------------------------------------------------------------
    function na_markCustomPreset() {
        if (naState.suppressChange) { return; }
        if (naState.settings.preset_key === 'custom') { return; }

        naState.settings.preset_key = 'custom';
        na_el('naSceneExp_preset').value = 'custom';
        na_updatePresetHint();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Copy a Preset's Settings Into the Live Settings Hash
    // ------------------------------------------------------------
    function na_applyPreset(presetKey) {
        var matched = naState.choices.presets.filter(function (record) { return record.key === presetKey; });
        if (!matched.length) { return; }

        var presetSettings = matched[0].settings || {};
        Object.keys(presetSettings).forEach(function (settingKey) {
            naState.settings[settingKey] = presetSettings[settingKey];
        });

        naState.settings.preset_key = presetKey;
        na_applySettingsToForm();
        na_saveSettings();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Push the Settings Hash to Ruby, Debounced
    // ------------------------------------------------------------
    function na_saveSettings() {
        if (naState.saveTimer) { window.clearTimeout(naState.saveTimer); }

        naState.saveTimer = window.setTimeout(function () {
            naState.saveTimer = null;
            if (!window.sketchup || !window.sketchup.na_save_settings) { return; }

            window.sketchup.na_save_settings(JSON.stringify(naState.settings));
        }, NA_SAVE_DEBOUNCE_MS);
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Control Wiring
    // -------------------------------------------------------------------------

    // FUNCTION | Attach Every Control and Button Listener
    // ------------------------------------------------------------
    function na_attachListeners() {

        // ----- Scene list controls -------------------------------------------

        na_el('naSceneExp_btnAllOn').addEventListener('click',  function () { na_setAllTicked('on');     });
        na_el('naSceneExp_btnAllOff').addEventListener('click', function () { na_setAllTicked('off');    });
        na_el('naSceneExp_btnInvert').addEventListener('click', function () { na_setAllTicked('invert'); });
        na_el('naSceneExp_sceneFilter').addEventListener('input', na_applySceneFilter);

        na_el('naSceneExp_btnRefresh').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_refresh_scenes) {
                window.sketchup.na_refresh_scenes('');
            }
        });

        // ----- Preset --------------------------------------------------------

        na_el('naSceneExp_preset').addEventListener('change', function (event) {
            na_applyPreset(event.target.value);
        });

        // ----- Size ----------------------------------------------------------

        na_el('naSceneExp_heightStep').addEventListener('change', function (event) {
            if (!event.target.value) { return; }                                    // <-- "Custom height" entry, leave the number alone

            naState.settings.image_height = parseInt(event.target.value, 10);
            na_el('naSceneExp_heightCustom').value = naState.settings.image_height;
            na_markCustomPreset();
            na_saveSettings();
        });

        na_el('naSceneExp_heightCustom').addEventListener('change', function (event) {
            naState.settings.image_height = na_clampNumber(
                parseInt(event.target.value, 10),
                naState.choices.min_pixels,
                naState.choices.max_pixels,
                4096
            );
            event.target.value = naState.settings.image_height;
            na_el('naSceneExp_heightStep').value = na_matchingHeightStep(naState.settings.image_height);
            na_markCustomPreset();
            na_saveSettings();
        });

        na_el('naSceneExp_aspectMode').addEventListener('change', function (event) {
            naState.settings.aspect_mode = event.target.value;
            na_markCustomPreset();
            na_syncConditionalFields();
            na_saveSettings();
        });

        na_el('naSceneExp_aspectW').addEventListener('change', function (event) {
            naState.settings.custom_aspect_width = na_clampNumber(parseInt(event.target.value, 10), 1, 10000, 16);
            event.target.value = naState.settings.custom_aspect_width;
            na_markCustomPreset();
            na_saveSettings();
        });

        na_el('naSceneExp_aspectH').addEventListener('change', function (event) {
            naState.settings.custom_aspect_height = na_clampNumber(parseInt(event.target.value, 10), 1, 10000, 9);
            event.target.value = naState.settings.custom_aspect_height;
            na_markCustomPreset();
            na_saveSettings();
        });

        // ----- Format and line weight ----------------------------------------

        na_el('naSceneExp_fileFormat').addEventListener('change', function (event) {
            naState.settings.file_format = event.target.value;
            na_markCustomPreset();
            na_syncConditionalFields();
            na_saveSettings();
        });

        na_el('naSceneExp_jpegQuality').addEventListener('input', function (event) {
            naState.settings.jpeg_quality = parseFloat(event.target.value);
            na_el('naSceneExp_jpegQualityValue').textContent = naState.settings.jpeg_quality.toFixed(2);
            na_markCustomPreset();
            na_saveSettings();
        });

        na_el('naSceneExp_lineScale').addEventListener('input', function (event) {
            naState.settings.line_scale_factor = parseFloat(event.target.value);
            na_el('naSceneExp_lineScaleValue').textContent = naState.settings.line_scale_factor.toFixed(1) + 'x';
            na_markCustomPreset();
            na_saveSettings();
        });

        na_el('naSceneExp_transparent').addEventListener('change', function (event) {
            naState.settings.transparent_background = !!event.target.checked;
            na_markCustomPreset();
            na_saveSettings();
        });

        // ----- Render override companions ------------------------------------

        na_el('naSceneExp_silhouetteWidth').addEventListener('change', function (event) {
            naState.settings.silhouette_width = na_clampNumber(parseInt(event.target.value, 10), 1, 15, 2);
            event.target.value = naState.settings.silhouette_width;
            na_markCustomPreset();
            na_saveSettings();
        });

        na_el('naSceneExp_lineExtension').addEventListener('change', function (event) {
            naState.settings.line_extension_amount = na_clampNumber(parseInt(event.target.value, 10), 0, 100, 4);
            event.target.value = naState.settings.line_extension_amount;
            na_markCustomPreset();
            na_saveSettings();
        });

        // ----- File naming ---------------------------------------------------

        na_el('naSceneExp_filenamePattern').addEventListener('input', function (event) {
            naState.settings.filename_pattern = event.target.value;
            na_saveSettings();
        });

        na_el('naSceneExp_overwriteMode').addEventListener('change', function (event) {
            naState.settings.overwrite_mode = event.target.value;
            na_saveSettings();
        });

        // ----- Export bar ----------------------------------------------------

        na_el('naSceneExp_btnBrowse').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_choose_folder) {
                window.sketchup.na_choose_folder('');
            }
        });

        na_el('naSceneExp_btnOpenFolder').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_open_folder) {
                window.sketchup.na_open_folder(naState.settings.export_folder || '');
            }
        });

        na_el('naSceneExp_btnExport').addEventListener('click', na_startExport);

        na_el('naSceneExp_btnCancel').addEventListener('click', function () {
            if (window.sketchup && window.sketchup.na_cancel_export) {
                window.sketchup.na_cancel_export('');
            }
        });
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Clamp a Numeric Input With a Fallback for NaN
    // ------------------------------------------------------------
    function na_clampNumber(value, minimumValue, maximumValue, fallbackValue) {
        if (isNaN(value)) { return fallbackValue; }
        if (value < minimumValue) { return minimumValue; }
        if (value > maximumValue) { return maximumValue; }
        return value;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Export Actions
    // -------------------------------------------------------------------------

    // FUNCTION | Validate Locally Then Ask Ruby to Start the Batch Export
    // ------------------------------------------------------------
    function na_startExport() {
        var tickedNames = na_tickedSceneNames();

        if (!tickedNames.length) {
            na_setStatus('Tick at least one scene before exporting.', 'warn');
            return;
        }
        if (!naState.settings.export_folder) {
            na_setStatus('Choose an export folder before exporting.', 'warn');
            return;
        }
        if (!window.sketchup || !window.sketchup.na_start_export) {
            na_setStatus('SketchUp bridge unavailable (browser preview mode).', 'error');
            return;
        }

        na_setRunningState(true);
        window.sketchup.na_start_export(JSON.stringify({
            scene_names : tickedNames,
            settings    : naState.settings
        }));
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Lock or Unlock the UI While an Export Runs
    // ------------------------------------------------------------
    function na_setRunningState(isRunning) {
        naState.isRunning = isRunning;
        na_el('naSceneExp_btnCancel').disabled = !isRunning;
        na_updateExportButtonState();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Enable the Export Button Only When a Run Is Possible
    // ------------------------------------------------------------
    function na_updateExportButtonState() {
        var exportButton = na_el('naSceneExp_btnExport');
        var tickedCount  = na_tickedSceneNames().length;
        var hasFolder    = !!(naState.settings && naState.settings.export_folder);

        exportButton.disabled  = naState.isRunning || tickedCount === 0 || !hasFolder;
        exportButton.textContent = tickedCount
            ? 'Export ' + tickedCount + ' Scene' + (tickedCount === 1 ? '' : 's')
            : 'Export Ticked Scenes';
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Move the Progress Bar and Its Caption
    // ------------------------------------------------------------
    function na_setProgress(donePercent, captionText, variantName) {
        var fillElement = na_el('naSceneExp_progressFill');
        fillElement.style.width = Math.max(0, Math.min(100, donePercent)) + '%';
        fillElement.className   = 'naSceneExp__ProgressFill'
            + (variantName ? ' naSceneExp__ProgressFill--' + variantName : '');
        na_el('naSceneExp_progressText').textContent = captionText;
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Write a Message Into the Status Bar
    // ------------------------------------------------------------
    function na_setStatus(messageText, variantName) {
        var statusElement = na_el('naSceneExp_status');
        statusElement.textContent = messageText;
        statusElement.className   = 'naSceneExp__StatusText'
            + (variantName && variantName !== 'info' ? ' naSceneExp__StatusText--' + variantName : '');
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Ruby To JavaScript Entry Points
    // -------------------------------------------------------------------------

    // FUNCTION | Receive the Full State Payload From Ruby
    // ------------------------------------------------------------
    window.Na__SceneExporter__ReceivePayload = function (payload) {
        naState.choices   = payload.choices;
        naState.settings  = payload.settings;
        naState.scenes    = payload.scenes || [];
        naState.modelInfo = payload.model;
        naState.isRunning = !!payload.is_running;

        naState.selectedNames = {};
        naState.scenes.forEach(function (sceneRecord) {
            if (sceneRecord.selected) { naState.selectedNames[sceneRecord.name] = true; }
        });

        na_buildChoiceLists();
        na_applySettingsToForm();
        na_renderSceneList();
        na_updateModelMeta(payload);
        na_updateResolved(payload.resolved);
        na_setRunningState(naState.isRunning);

        na_setStatus('Ready. Tick the scenes you want, then press Export.', 'info');
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive an Export Progress Update From Ruby
    // ------------------------------------------------------------
    window.Na__SceneExporter__ReceiveProgress = function (status) {
        var totalCount = Number(status.total || 0);
        var doneCount  = Number(status.done  || 0);
        var percent    = totalCount ? (doneCount / totalCount) * 100 : 0;

        if (status.phase === 'complete' || status.phase === 'cancelled') {
            na_setProgress(100, status.message, status.phase === 'complete' ? 'done' : null);
            na_setStatus(status.message, status.failed ? 'warn' : 'success');
            na_setRunningState(false);
            na_reportFailures(status);
            if (status.last_export && status.written) {
                na_el('naSceneExp_lastExport').textContent =
                    'Last export: ' + status.written + ' file(s), ' + status.last_export;
            }
            return;
        }

        if (status.phase === 'error') {
            na_setProgress(100, status.message, 'error');
            na_setStatus(status.message, 'error');
            na_setRunningState(false);
            return;
        }

        na_setProgress(percent, status.message, null);
        na_setStatus(status.message, 'info');
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive a Status Bar Message From Ruby
    // ------------------------------------------------------------
    window.Na__SceneExporter__ReceiveStatus = function (messageText, variantName) {
        na_setStatus(messageText, variantName);
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive the Recalculated Output Size and Sample Filename
    // ------------------------------------------------------------
    window.Na__SceneExporter__ReceiveResolved = function (resolved) {
        na_updateResolved(resolved);
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive a Newly Chosen Export Folder From Ruby
    // ------------------------------------------------------------
    window.Na__SceneExporter__ReceiveFolder = function (payload) {
        naState.settings.export_folder = payload.folder || '';
        na_el('naSceneExp_folderPath').value = naState.settings.export_folder;
        na_updateExportButtonState();
    };
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Readout Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Refresh the Resolved Size and Sample Filename Lines
    // ------------------------------------------------------------
    function na_updateResolved(resolved) {
        if (!resolved) { return; }

        var megapixels = (Number(resolved.width) * Number(resolved.height)) / 1000000;
        na_el('naSceneExp_sizeReadout').textContent =
            'Resolved size: ' + resolved.width + ' x ' + resolved.height +
            ' px  (' + megapixels.toFixed(1) + ' MP)';

        if (resolved.sample_file_name) {
            na_el('naSceneExp_sampleName').textContent = 'Example: ' + resolved.sample_file_name;
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Summarise the Model in the Toolbar
    // ------------------------------------------------------------
    function na_updateModelMeta(payload) {
        var modelInfo = payload.model || {};
        var metaParts = [];

        metaParts.push(modelInfo.name || 'Untitled');
        metaParts.push(modelInfo.scene_count + ' scene' + (modelInfo.scene_count === 1 ? '' : 's'));
        if (!modelInfo.is_saved) { metaParts.push('model not saved yet'); }

        na_el('naSceneExp_modelMeta').textContent = metaParts.join('  -  ');

        var lastExport = payload.last_export || {};
        na_el('naSceneExp_lastExport').textContent = lastExport.time
            ? 'Last export: ' + lastExport.count + ' file(s), ' + lastExport.time
            : '';
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Log Per-Scene Failures Back to the Ruby Console
    // ------------------------------------------------------------
    function na_reportFailures(status) {
        if (!status.failures || !status.failures.length) { return; }

        status.failures.forEach(function (failureRecord) {
            na_log('Scene failed: ' + failureRecord.scene + ' - ' + failureRecord.reason);
        });
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Boot
    // -------------------------------------------------------------------------

    // FUNCTION | Initialise the Dialog on DOMContentLoaded
    // ------------------------------------------------------------
    function na_boot() {
        na_attachListeners();
        na_updateExportButtonState();                                               // <-- Starts disabled until a payload arrives

        if (window.sketchup && window.sketchup.na_dialog_ready) {
            window.sketchup.na_dialog_ready('');                                    // <-- Ask Ruby to push the model payload
        } else {
            na_setStatus('SketchUp bridge not found; running in browser preview mode.', 'warn');
        }
    }
    // ------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', na_boot);

    // endregion ---------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
