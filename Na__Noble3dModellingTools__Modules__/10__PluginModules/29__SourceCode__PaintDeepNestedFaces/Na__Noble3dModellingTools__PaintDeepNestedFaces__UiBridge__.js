// =============================================================================
// NA NOBLE3D MODELLING TOOLS - PAINT DEEP NESTED FACES - UI BRIDGE
// =============================================================================
//
// FILE       : Na__Noble3dModellingTools__PaintDeepNestedFaces__UiBridge__.js
// NAMESPACE  : window.Na__PaintFaces__* (Ruby-facing entry points)
// AUTHOR     : Adam Noble - Noble Architecture
// PURPOSE    : Render the active material preview, the nesting toggles and the
//              live selection readout from the Ruby payload, and send every
//              user action straight back to Ruby.
// CREATED    : 2026
//
// RUBY -> JS : Na__PaintFaces__ReceivePayload(payload)
//              Na__PaintFaces__ReceiveMaterial(material)
//              Na__PaintFaces__ReceiveSelection(selection)
//              Na__PaintFaces__ReceiveStatus(message, variant)
// JS -> RUBY : sketchup.na_dialog_ready      / na_refresh
//              sketchup.na_set_deep_nesting  / na_set_isolate_shared
//              sketchup.na_paint_faces       / na_js_log
//
// =============================================================================

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var naState = {
        material  : null,                                                           // <-- Latest material payload from Ruby
        selection : null,                                                           // <-- Latest selection summary from Ruby
        settings  : { deep_nesting: true, isolate_shared: false }
    };

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Shorthand for getElementById
    // ------------------------------------------------------------
    function na_el(elementId) { return document.getElementById(elementId); }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Write Text Into an Element When It Exists
    // ------------------------------------------------------------
    function na_setText(elementId, textValue) {
        var element = na_el(elementId);
        if (element) { element.textContent = textValue; }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Toggle a Modifier Class on an Element
    // ------------------------------------------------------------
    function na_setModifier(elementId, modifierClass, isOn) {
        var element = na_el(elementId);
        if (!element) { return; }

        if (isOn) {
            element.classList.add(modifierClass);
        } else {
            element.classList.remove(modifierClass);
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Send a Log Line to the Ruby Console
    // ------------------------------------------------------------
    function na_log(message) {
        if (window.sketchup && window.sketchup.na_js_log) {
            window.sketchup.na_js_log(String(message));
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Call a Ruby Action Callback When It Is Available
    // ------------------------------------------------------------
    function na_callRuby(callbackName, argumentValue) {
        if (!window.sketchup || !window.sketchup[callbackName]) { return; }

        if (arguments.length > 1) {
            window.sketchup[callbackName](argumentValue);
        } else {
            window.sketchup[callbackName]();
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Material Preview Rendering
    // -------------------------------------------------------------------------

    // FUNCTION | Render the Active Material Card and the Back Face Rule
    // ------------------------------------------------------------
    function na_renderMaterial(materialPayload) {
        naState.material = materialPayload || null;

        if (!materialPayload || !materialPayload.has_material) {
            na_renderEmptyMaterial();
            na_updatePaintButton();
            return;
        }

        na_setModifier('naPaintFaces_materialCard', 'naPaintFaces__MaterialCard--empty', false);
        na_setText('naPaintFaces_materialName',    materialPayload.name);
        na_setText('naPaintFaces_materialHex',     materialPayload.hex);
        na_setText('naPaintFaces_materialOpacity', materialPayload.opacity_percent + '% opacity');
        na_setText('naPaintFaces_materialType',    materialPayload.material_type);
        na_setText('naPaintFaces_materialNote',    na_materialNoteText(materialPayload));

        na_paintSwatch(materialPayload);
        na_renderRuleBanner(materialPayload);
        na_updatePaintButton();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Render the Tray-Unreadable State
    // ------------------------------------------------------------
    // Rare. The Default swatch is a real material here, so an empty tray is not
    // what lands in this state - only a model that cannot be read at all.
    // ------------------------------------------------------------
    function na_renderEmptyMaterial() {
        na_setModifier('naPaintFaces_materialCard', 'naPaintFaces__MaterialCard--empty', true);
        na_setText('naPaintFaces_materialName',    'Materials tray unavailable');
        na_setText('naPaintFaces_materialHex',     '-');
        na_setText('naPaintFaces_materialOpacity', '-');
        na_setText('naPaintFaces_materialType',    '-');
        na_setText('naPaintFaces_materialNote',
            'The active material could not be read. Click a swatch in the SketchUp Materials tray, ' +
            'then press Refresh.');

        var swatchElement = na_el('naPaintFaces_swatchFill');
        if (swatchElement) { swatchElement.style.background = 'transparent'; }

        na_setModifier('naPaintFaces_ruleBanner', 'naPaintFaces__RuleBanner--transparent', false);
        na_setModifier('naPaintFaces_ruleBanner', 'naPaintFaces__RuleBanner--default',     false);
        na_setText('naPaintFaces_ruleBadge', 'Waiting');
        na_setText('naPaintFaces_ruleText',  'Pick a material to see which back face rule will apply.');
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Fill the Swatch With the Colour at Its Real Opacity
    // ------------------------------------------------------------
    // The checkerboard behind the fill makes the alpha value readable at a
    // glance, which is the whole reason opacity is tracked in this tool.
    // The Default material has no colour of its own, so it is drawn the way
    // SketchUp draws it: the front face colour split diagonally against the
    // back face colour, both read from the model rendering options.
    // ------------------------------------------------------------
    function na_paintSwatch(materialPayload) {
        var swatchElement = na_el('naPaintFaces_swatchFill');
        if (!swatchElement) { return; }

        if (materialPayload.is_default) {
            swatchElement.style.background = 'linear-gradient(45deg, ' +
                materialPayload.back_hex + ' 0 50%, ' + materialPayload.hex + ' 50% 100%)';
            return;
        }

        var rgbValues = materialPayload.rgb || [180, 180, 180];
        swatchElement.style.background = 'rgba(' +
            rgbValues[0] + ', ' + rgbValues[1] + ', ' + rgbValues[2] + ', ' +
            materialPayload.alpha + ')';
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Render the Front / Back Face Rule Banner
    // ------------------------------------------------------------
    function na_renderRuleBanner(materialPayload) {
        var faceRule      = materialPayload.back_face_rule;
        var isTransparent = faceRule === 'paint_both';
        var isDefault     = faceRule === 'strip_both';

        na_setModifier('naPaintFaces_ruleBanner', 'naPaintFaces__RuleBanner--transparent', isTransparent);
        na_setModifier('naPaintFaces_ruleBanner', 'naPaintFaces__RuleBanner--default',     isDefault);

        if (isDefault) {
            na_setText('naPaintFaces_ruleBadge', 'Default');
            na_setText('naPaintFaces_ruleText',
                'Front and back both cleared, stripping the material off every face reached.');
            return;
        }

        na_setText('naPaintFaces_ruleBadge', isTransparent ? 'Transparent' : 'Opaque');
        na_setText('naPaintFaces_ruleText', isTransparent
            ? 'Front and back faces both painted, so the material reads correctly from either side.'
            : 'Front face painted, back face stripped to default.');
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Build the Small Print Under the Material Name
    // ------------------------------------------------------------
    function na_materialNoteText(materialPayload) {
        var notes = [];

        if (materialPayload.is_default) {
            notes.push('SketchUp represents the default material as no material at all, so this strips ' +
                       'whatever is already on the faces rather than painting them.');
        }

        if (materialPayload.is_textured) {
            var textureName = materialPayload.texture_name ? ' (' + materialPayload.texture_name + ')' : '';
            notes.push('Textured material' + textureName +
                       '. The swatch shows the average texture colour; the full texture is applied unchanged.');
        }

        if (materialPayload.has_material && !materialPayload.in_model) {
            notes.push('This swatch comes from a material library and is not in the model yet. ' +
                       'It will be copied in before any face is painted.');
        }

        return notes.join(' ');
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Selection Readout Rendering
    // -------------------------------------------------------------------------

    // FUNCTION | Render the Live Selection Statistics and Notes
    // ------------------------------------------------------------
    function na_renderSelection(selectionPayload) {
        naState.selection = selectionPayload || null;

        var summary = selectionPayload || { face_count: 0, container_count: 0, deepest_level: 0 };

        na_setText('naPaintFaces_statFaces',      na_faceCountText(summary));
        na_setText('naPaintFaces_statContainers', na_formatNumber(summary.container_count));
        na_setText('naPaintFaces_statDepth',      na_formatNumber(summary.deepest_level));

        na_renderSelectionNotes(summary);
        na_updatePaintButton();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Build the Bullet Notes Under the Statistics
    // ------------------------------------------------------------
    function na_renderSelectionNotes(summary) {
        var listElement = na_el('naPaintFaces_selectionNotes');
        if (!listElement) { return; }

        listElement.innerHTML = '';

        if (!summary.has_selection) {
            na_appendNote(listElement, 'Nothing is selected. Select groups, components or faces in the model.', false);
            return;
        }

        if (summary.face_count === 0) {
            na_appendNote(listElement, naState.settings.deep_nesting
                ? 'No faces found anywhere in this selection.'
                : 'No faces found one level in. Turn Deep Nesting on to reach faces further down.', true);
        }

        if (summary.direct_face_count > 0) {
            na_appendNote(listElement, summary.direct_face_count +
                ' directly selected ' + na_pluralise(summary.direct_face_count, 'face', 'faces') +
                ' included.', false);
        }

        if (summary.skipped_container_count > 0) {
            na_appendNote(listElement, summary.skipped_container_count + ' nested ' +
                na_pluralise(summary.skipped_container_count, 'container', 'containers') +
                ' left untouched because Deep Nesting is off.', false);
        }

        if (summary.locked_container_count > 0) {
            na_appendNote(listElement, summary.locked_container_count + ' locked ' +
                na_pluralise(summary.locked_container_count, 'container', 'containers') +
                ' will be skipped.', true);
        }

        if (summary.shared_definition_count > 0) {
            na_appendNote(listElement, na_sharedNoteText(summary), true);
        }

        if (summary.limit_reached) {
            na_appendNote(listElement, 'Live count stopped at ' + na_formatNumber(summary.preview_limit) +
                ' faces to keep this dialog responsive. Painting still covers the whole selection.', false);
        }
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Word the Face Count, Marking a Capped Preview
    // ------------------------------------------------------------
    function na_faceCountText(summary) {
        return na_formatNumber(summary.face_count) + (summary.limit_reached ? '+' : '');
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Word the Shared Component Warning
    // ------------------------------------------------------------
    function na_sharedNoteText(summary) {
        var sharedCount = summary.shared_definition_count;
        var otherCount  = summary.other_instance_count;

        if (naState.settings.isolate_shared) {
            return sharedCount + ' shared ' + na_pluralise(sharedCount, 'definition', 'definitions') +
                   ' will be made unique first, leaving other placements alone.';
        }

        return sharedCount + ' shared ' + na_pluralise(sharedCount, 'definition', 'definitions') +
               ' in this selection. Painting inside will also change ' + otherCount + ' other ' +
               na_pluralise(otherCount, 'placement', 'placements') + '.';
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Append One Bullet Note to the List
    // ------------------------------------------------------------
    function na_appendNote(listElement, noteText, isWarning) {
        var noteElement = document.createElement('div');
        noteElement.className   = 'naPaintFaces__Note' + (isWarning ? ' naPaintFaces__Note--warn' : '');
        noteElement.textContent = noteText;
        listElement.appendChild(noteElement);
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Settings and Action Button
    // -------------------------------------------------------------------------

    // FUNCTION | Apply the Persisted Toggle State to the Controls
    // ------------------------------------------------------------
    function na_renderSettings(settingsPayload) {
        if (!settingsPayload) { return; }

        naState.settings = settingsPayload;

        var deepElement    = na_el('naPaintFaces_deepNesting');
        var isolateElement = na_el('naPaintFaces_isolateShared');

        if (deepElement)    { deepElement.checked    = !!settingsPayload.deep_nesting; }
        if (isolateElement) { isolateElement.checked = !!settingsPayload.isolate_shared; }

        na_renderDeepHint();
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Word the Deep Nesting Hint for the Current Mode
    // ------------------------------------------------------------
    function na_renderDeepHint() {
        na_setText('naPaintFaces_deepHint', naState.settings.deep_nesting
            ? 'On: every face at every level below the selection is painted.'
            : 'Off: only the faces directly inside each selected container are painted.');
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Enable and Label the Paint Button for the Current State
    // ------------------------------------------------------------
    // The Default material strips rather than paints, so every label and the
    // face count caption switch verb with it.
    // ------------------------------------------------------------
    function na_updatePaintButton() {
        var buttonElement = na_el('naPaintFaces_btnPaint');
        if (!buttonElement) { return; }

        var hasMaterial = !!(naState.material && naState.material.has_material);
        var isDefault   = !!(naState.material && naState.material.is_default);
        var faceCount   = naState.selection ? naState.selection.face_count : 0;
        var isCapped    = !!(naState.selection && naState.selection.limit_reached);
        var actionWord  = isDefault ? 'Strip' : 'Paint';

        buttonElement.disabled = !(hasMaterial && faceCount > 0);
        na_setText('naPaintFaces_statFacesLabel', isDefault ? 'faces to strip' : 'faces to paint');

        if (!hasMaterial) {
            buttonElement.textContent = 'Pick a Material First';
        } else if (faceCount === 0) {
            buttonElement.textContent = 'No Faces to ' + actionWord;
        } else if (isCapped) {
            buttonElement.textContent = actionWord + ' All Faces in Selection';
        } else {
            buttonElement.textContent = actionWord + ' ' + na_formatNumber(faceCount) + ' ' +
                                        na_pluralise(faceCount, 'Face', 'Faces');
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Formatting Helpers
    // -------------------------------------------------------------------------

    // HELPER FUNCTION | Group Thousands So Large Face Counts Stay Readable
    // ------------------------------------------------------------
    function na_formatNumber(numberValue) {
        return String(numberValue || 0).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }
    // ------------------------------------------------------------

    // HELPER FUNCTION | Pick the Singular or Plural Word for a Count
    // ------------------------------------------------------------
    function na_pluralise(countValue, singularWord, pluralWord) {
        return countValue === 1 ? singularWord : pluralWord;
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Event Wiring
    // -------------------------------------------------------------------------

    // FUNCTION | Bind Every Control to Its Ruby Callback
    // ------------------------------------------------------------
    function na_bindEvents() {
        var refreshElement = na_el('naPaintFaces_btnRefresh');
        var paintElement   = na_el('naPaintFaces_btnPaint');
        var deepElement    = na_el('naPaintFaces_deepNesting');
        var isolateElement = na_el('naPaintFaces_isolateShared');

        if (refreshElement) {
            refreshElement.addEventListener('click', function () {
                na_callRuby('na_refresh');
            });
        }

        if (paintElement) {
            paintElement.addEventListener('click', function () {
                if (paintElement.disabled) { return; }

                var isDefault = !!(naState.material && naState.material.is_default);
                Na__PaintFaces__ReceiveStatus(isDefault ? 'Stripping...' : 'Painting...', 'info');
                na_callRuby('na_paint_faces');
            });
        }

        if (deepElement) {
            deepElement.addEventListener('change', function () {
                naState.settings.deep_nesting = deepElement.checked;
                na_renderDeepHint();
                na_callRuby('na_set_deep_nesting', String(deepElement.checked));
            });
        }

        if (isolateElement) {
            isolateElement.addEventListener('change', function () {
                naState.settings.isolate_shared = isolateElement.checked;
                na_callRuby('na_set_isolate_shared', String(isolateElement.checked));
            });
        }
    }
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Ruby Facing Entry Points
    // -------------------------------------------------------------------------

    // FUNCTION | Receive the Complete Dialog State
    // ------------------------------------------------------------
    window.Na__PaintFaces__ReceivePayload = function (payload) {
        if (!payload) { return; }

        na_renderSettings(payload.settings);
        na_renderMaterial(payload.material);
        na_renderSelection(payload.selection);
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive a Material Preview Update Only
    // ------------------------------------------------------------
    window.Na__PaintFaces__ReceiveMaterial = function (materialPayload) {
        na_renderMaterial(materialPayload);
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive a Selection Summary Update Only
    // ------------------------------------------------------------
    window.Na__PaintFaces__ReceiveSelection = function (selectionPayload) {
        na_renderSelection(selectionPayload);
    };
    // ------------------------------------------------------------

    // FUNCTION | Receive a Status Line for the Dialog Footer
    // ------------------------------------------------------------
    window.Na__PaintFaces__ReceiveStatus = function (message, variant) {
        var statusElement = na_el('naPaintFaces_status');
        if (!statusElement) { return; }

        statusElement.textContent = message;
        statusElement.className   = 'naPaintFaces__StatusText' +
            (variant && variant !== 'info' ? ' naPaintFaces__StatusText--' + variant : '');
    };
    // ------------------------------------------------------------

    // endregion ---------------------------------------------------------------


    // -------------------------------------------------------------------------
    // REGION | Boot
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function () {
        na_bindEvents();
        na_renderDeepHint();
        na_updatePaintButton();
        na_log('Paint Deep Nested Faces dialog ready.');
        na_callRuby('na_dialog_ready');
    });

    // endregion ---------------------------------------------------------------

})();

// =============================================================================
// END OF FILE
// =============================================================================
