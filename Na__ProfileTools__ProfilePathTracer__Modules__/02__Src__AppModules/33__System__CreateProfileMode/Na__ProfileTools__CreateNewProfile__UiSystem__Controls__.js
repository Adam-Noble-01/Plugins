/* =============================================================================
   NA PROFILE TOOLS - CREATE NEW PROFILE - UI SYSTEM - CONTROLS
   =============================================================================
   FILE       : Na__ProfileTools__CreateNewProfile__UiSystem__Controls__.js
   NAMESPACE  : window.Na__ProfilePathTracer__Ui__Controls
   PURPOSE    : Render UI controls for the Apply Profile tab and the
                Create New Profile form panel.
   ============================================================================= */

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | HTML Helpers
    // -------------------------------------------------------------------------

    // Two-state segmented switch. Both choices stay visible and the live one is
    // filled in, so the current mode and its alternative read in a single glance
    // — no click needed, unlike the dropdowns these replaced.
    function Na__Ui__BuildSwitchHtml(switchKey, options, activeValue) {
        const buttons = options.map(function(option) {
            const isActive = String(option.value) === String(activeValue);
            const activeClass = isActive ? ' na-switch__option--active' : '';
            return [
                '<button type="button"',
                '        class="na-switch__option' + activeClass + '"',
                '        data-na-switch-key="' + switchKey + '"',
                '        data-na-switch-value="' + option.value + '"',
                '        aria-pressed="' + (isActive ? 'true' : 'false') + '"',
                '        title="' + (option.title || option.label) + '">',
                option.shortLabel || option.label,
                '</button>'
            ].join(' ');
        }).join('');

        return '<div class="na-switch" role="group">' + buttons + '</div>';
    }

    function Na__Ui__BuildSwitchOptions(configOptions, shortLabels) {
        return (configOptions || []).map(function(option) {
            return {
                value: option.value,
                label: option.label,
                title: option.label,
                shortLabel: shortLabels[option.value] || option.label
            };
        });
    }

    function Na__Ui__BuildToggleButtonsHtml(toggleDefinitions, toggleStates) {
        const toggleKeys = Object.keys(toggleDefinitions || {});
        if (toggleKeys.length === 0) return '';

        return toggleKeys.map(function(toggleKey) {
            const toggleMeta = toggleDefinitions[toggleKey] || {};
            const isActive = !!toggleStates[toggleKey];
            const activeClass = isActive ? ' na-toggle-btn--active' : '';
            const ariaPressed = isActive ? 'true' : 'false';
            const safeLabel = toggleMeta.text || toggleKey;
            const safeDescription = toggleMeta.description || '';

            return [
                '<button class="na-toggle-btn' + activeClass + '"',
                '        data-na-toggle-key="' + toggleKey + '"',
                '        aria-pressed="' + ariaPressed + '"',
                '        title="' + safeDescription + '">',
                safeLabel,
                '</button>'
            ].join(' ');
        }).join('');
    }

    function Na__Ui__BuildRotationPillsHtml(currentRotationStep) {
        const steps = [
            { step: 0, label: '0°' },
            { step: 1, label: '90°' },
            { step: 2, label: '180°' },
            { step: 3, label: '270°' }
        ];

        return steps.map(function(item) {
            const isActive = item.step === currentRotationStep;
            const activeClass = isActive ? ' na-rotation-pill--active' : '';
            return '<button class="na-rotation-pill' + activeClass + '" data-na-rotation-step="' + item.step + '">' + item.label + '</button>';
        }).join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Controls Renderer (Apply Profile Tab body)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Bound Trace Strip (profile hot swap)
    // -------------------------------------------------------------------------

    // Rendered above everything else when a placed trace is bound, because it
    // changes what every control below it means: the pills, mirrors and insert
    // point now describe an assembly standing in the model, and Regenerate
    // Trace is what writes them to it.
    function Na__Ui__BuildBoundTraceHtml(swapState) {
        if (!swapState || swapState.isBound !== true) return '';

        var controller = window.Na__ProfileTools__SwapController;
        var label      = controller ? controller.Na__Swap__TraceLabel() : (swapState.primaryTraceId || '');
        var dirtyHint  = swapState.isDirty
            ? '<span class="na-bound-trace__dirty">Unapplied changes — click Regenerate Trace</span>'
            : '<span class="na-bound-trace__clean">In sync with the model</span>';

        return [
            '<div class="na-section na-bound-trace' + (swapState.isDirty ? ' na-bound-trace--dirty' : '') + '">',
            '  <div class="na-bound-trace__body">',
            '    <span class="na-bound-trace__label">Bound Trace</span>',
            '    <span class="na-bound-trace__name">' + Na__Ui__EscapeHtml(label) + '</span>',
            '    ' + dirtyHint,
            '  </div>',
            '  <button class="naButtonSecondary na-bound-trace__unbind" id="naBtnUnbindTrace"',
            '          title="Stop editing this placed trace. The Apply Profile tab goes back to generating new ones.">Unbind</button>',
            '</div>'
        ].join('');
    }

    function Na__Ui__BuildSwapArmedHtml(swapState) {
        if (!swapState || swapState.isArmed !== true) return '';
        return [
            '<div class="na-section na-swap-armed">',
            '  <span class="na-swap-armed__text">Waiting for a replacement profile — pick one in the Gallery.</span>',
            '  <button class="naButtonSecondary" id="naBtnCancelSwapArm">Cancel</button>',
            '</div>'
        ].join('');
    }

    function Na__Ui__EscapeHtml(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Selection Preview Strip
    // -------------------------------------------------------------------------

    function Na__Ui__IsSelectionPreviewLive(state) {
        return !!(state && state.isInteractiveToolActive === true && state.liveToolKind === 'selectionPreview');
    }

    // Shown while a Selection preview is running, because it changes what the
    // buttons below mean: nothing is in the model yet, and the choice now is
    // Commit or Cancel. Every control in between edits the preview live.
    function Na__Ui__BuildSelectionPreviewStripHtml(state) {
        if (!Na__Ui__IsSelectionPreviewLive(state)) return '';
        return [
            '<div class="na-section na-preview-strip">',
            '  <div class="na-preview-strip__body">',
            '    <span class="na-preview-strip__label">Previewing Selection</span>',
            '    <span class="na-preview-strip__summary">' + Na__Ui__EscapeHtml(state.livePathSummary || '') + '</span>',
            '  </div>',
            '  <span class="na-preview-strip__hint">Nothing is built yet. Change the profile, Reverse, rotation, mirrors or offsets and the viewport follows; Commit Profile builds it.</span>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Active Profile Picker
    // -------------------------------------------------------------------------

    // A list rather than a label, so the profile can be changed without leaving
    // the tab — which is what lets it change mid-preview: pick another profile
    // and the sweep in the viewport redraws with it. Same order and same names
    // as the Gallery cards, so the two read as one list.
    function Na__Ui__BuildActiveProfileSelectHtml(activeKey) {
        var store    = window.Na__ProfileTools__ProfileStore;
        var profiles = store ? (store.Na__Store__GetProfiles() || {}) : {};
        var keys     = Object.keys(profiles);
        if (keys.length === 0) {
            return '<div class="na-active-profile" id="naActiveProfileIndicator">' +
                   '<span class="na-active-profile__hint">No profiles loaded — check the profile library folder.</span></div>';
        }

        var hasActive   = !!(activeKey && profiles[activeKey]);
        var placeholder = hasActive ? '' : '<option value="" selected disabled>Choose a profile…</option>';
        var options = keys.map(function(key) {
            var label = (store && store.Na__Store__ProfileLabel(profiles[key])) || key;
            return '<option value="' + Na__Ui__EscapeHtml(key) + '"' + (key === activeKey ? ' selected' : '') + '>' +
                   Na__Ui__EscapeHtml(label) + '</option>';
        }).join('');

        return [
            '<select class="naSelect na-active-profile-select" id="naSelectActiveProfile"',
            '        title="The profile to apply. Changing it while a preview is running redraws the preview. The Gallery tab picks from the same list with thumbnails.">',
            placeholder + options,
            '</select>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Path Offsets Row
    // -------------------------------------------------------------------------

    // Shown as typed, in millimetres, to one decimal place at most.
    function Na__Ui__FormatOffsetMm(value) {
        var rounded = Math.round((Number(value) || 0) * 10) / 10;
        return String(Object.is(rounded, -0) ? 0 : rounded);
    }

    function Na__Ui__BuildOffsetFieldHtml(endKey, label, value, tooltip) {
        var inputId = endKey === 'start' ? 'naInputStartOffset' : 'naInputEndOffset';
        var isSet   = (Number(value) || 0) !== 0;
        return [
            '<div class="na-offset-field">',
            '  <label class="na-switch-field__label" for="' + inputId + '">' + label + '</label>',
            '  <div class="na-offset-field__box' + (isSet ? ' na-offset-field__box--set' : '') + '">',
            '    <input class="na-offset-field__input" id="' + inputId + '" type="text" inputmode="decimal"',
            '           autocomplete="off" spellcheck="false" data-na-offset-end="' + endKey + '"',
            '           value="' + Na__Ui__FormatOffsetMm(value) + '" title="' + Na__Ui__EscapeHtml(tooltip) + '">',
            '    <span class="na-offset-field__unit">mm</span>',
            '  </div>',
            '</div>'
        ].join('');
    }

    // Both ends on one row, with a swap between them: in Selection mode which
    // end is Start is whatever the edges give, so the fix for an overshoot on
    // the wrong end is one click rather than retyping both boxes.
    function Na__Ui__BuildPathOffsetsHtml(state) {
        var startValue = Number(state.startOffsetMm) || 0;
        var endValue   = Number(state.endOffsetMm) || 0;
        var canSwap    = startValue !== endValue;

        return [
            '<div class="na-offset-row">',
            Na__Ui__BuildOffsetFieldHtml('start', 'Start Offset', startValue,
                'Run the profile past the START of an open path, in mm (0.15m or 6in work too). Negative trims it back. ' +
                'Interactive: Start is your first click. Selection: Start is tagged in the viewport preview.'),
            '  <button type="button" class="naButtonSecondary na-offset-row__swap" id="naBtnSwapPathOffsets"' + (canSwap ? '' : ' disabled'),
            '          title="Swap the Start and End offsets">&#8646;</button>',
            Na__Ui__BuildOffsetFieldHtml('end', 'End Offset', endValue,
                'Run the profile past the END of an open path, in mm (0.15m or 6in work too). Negative trims it back. ' +
                'Interactive: End is your last click. Selection: End is tagged in the viewport preview.'),
            '</div>',
            '<div class="na-offset-row__hint">Overshoot past the ends of an open path, e.g. a gutter past the verge. Negative values trim; closed loops ignore offsets.</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Main Controls Renderer
    // -------------------------------------------------------------------------

    function Na__Ui__RenderControls(state) {
        const config = window.Na__ProfilePathTracer__Ui__Config;
        const profileValue = state.profileKey || config.defaults.profileKey;
        const profileSourceModeValue = state.profileSourceMode || config.defaults.profileSourceMode || 'library';
        const pathModeValue = state.pathMode || config.defaults.pathMode;
        const toggleDefinitions = state.toggleDefinitions || config.toggleDefinitions || {};
        const toggleStates = state.toggleStates || config.defaults.toggleStates || {};
        const rotationStep = Number(state.rotationStep || 0) % 4;
        const isSceneMode = profileSourceModeValue === 'scene';
        const sceneStatus = state.sceneProfileStatus || {};
        const sceneProfileName = sceneStatus.displayName || 'No scene profile selected';
        const sceneProfileReady = sceneStatus.isValid === true;
        const sceneReadyClass = sceneProfileReady ? 'naSceneStatus--ready' : 'naSceneStatus--pending';
        const sceneHint = sceneProfileReady ? 'Scene source ready' : 'Pick scene source';

        const hasToggles = Object.keys(toggleDefinitions).length > 0;

        const isInsertPointPickActive = state.isInsertPointPickActive === true;
        const hasCustomInsertPoint    = !!state.originOffset;
        const insertPointHint         = hasCustomInsertPoint
            ? 'Custom datum: Y ' + Math.round(state.originOffset.y) + 'mm, Z ' + Math.round(state.originOffset.z) + 'mm'
            : 'Datum: profile origin';

        var store            = window.Na__ProfileTools__ProfileStore;
        var activeKey        = store ? store.Na__Store__GetSelectedKey() : '';
        var activeRecord     = store ? store.Na__Store__GetSelectedRecord() : null;
        var activeName       = activeRecord ? (activeRecord.displayName || activeRecord.profileKey || '') : '';
        var activeHint       = activeName
            ? '<span class="na-active-profile__name">' + activeName + '</span>'
            : '<span class="na-active-profile__hint">No profile selected — choose one in the Gallery.</span>';

        var swapState  = state.swap || null;
        var isBound    = !!(swapState && swapState.isBound);
        var isSwapBusy = !!(swapState && swapState.isBusy);
        var isPreviewLive = Na__Ui__IsSelectionPreviewLive(state);
        var isSelectionMode = pathModeValue === 'selection';

        return [
            Na__Ui__BuildSelectionPreviewStripHtml(state),
            Na__Ui__BuildBoundTraceHtml(swapState),
            Na__Ui__BuildSwapArmedHtml(swapState),

            '<div class="na-section na-section--controls">',

            // Scene mode takes its profile from the scene pick below, so the
            // library list would only offer choices that are not in use.
            '  <div class="naFormRow">',
            '    <label' + (isSceneMode ? '' : ' for="naSelectActiveProfile"') + '>Active Profile</label>',
            isSceneMode
                ? '    <div class="na-active-profile" id="naActiveProfileIndicator">' + activeHint + '</div>'
                : Na__Ui__BuildActiveProfileSelectHtml(activeKey),
            '  </div>',

            '  <div class="na-switch-row">',
            '    <div class="na-switch-field">',
            '      <span class="na-switch-field__label">Profile Source</span>',
            Na__Ui__BuildSwitchHtml(
                'profileSourceMode',
                Na__Ui__BuildSwitchOptions(config.profileSourceModeOptions, {
                    library: 'Library',
                    scene:   'Scene Pick'
                }),
                profileSourceModeValue
            ),
            '    </div>',
            '    <div class="na-switch-field">',
            '      <span class="na-switch-field__label">Path Mode</span>',
            Na__Ui__BuildSwitchHtml(
                'pathMode',
                Na__Ui__BuildSwitchOptions(config.pathModeOptions, {
                    selection:   'Selection',
                    interactive: 'Interactive'
                }),
                pathModeValue
            ),
            '    </div>',
            '  </div>',

            Na__Ui__BuildPathOffsetsHtml(state),

            '<div class="naSceneSourceWrap' + (isSceneMode ? '' : ' naSceneSourceWrap--hidden') + '">',
            '  <div class="naSceneStatus ' + sceneReadyClass + '">' + sceneHint + ': ' + sceneProfileName + '</div>',
            '  <div class="naSceneActions">',
            '    <button class="naButton" id="naBtnPickSceneProfile">Pick Scene Profile</button>',
            '    <button class="naButton naButtonSecondary" id="naBtnClearSceneProfile">Clear</button>',
            '  </div>',
            '</div>',

            '</div>',

            '<div class="na-section na-viewport-section">',
            '  <div class="naViewportWrap' + (isInsertPointPickActive ? ' naViewportWrap--picking' : '') + '">',
            '    <svg class="naViewportSvg" id="naProfileViewportSvg" viewBox="-120 -120 240 240"></svg>',
            '  </div>',
            '  <div class="naInsertPointBar">',
            '    <span class="naInsertPointBar__hint' + (hasCustomInsertPoint ? ' naInsertPointBar__hint--custom' : '') + '">' + insertPointHint + '</span>',
            '    <div class="naInsertPointBar__actions">',
            '      <button class="naButtonSecondary' + (isInsertPointPickActive ? ' naButton--pickActive' : '') + '"',
            '              id="naBtnSetInsertPoint"',
            '              title="Click a profile vertex in the preview to move the insertion point there">',
            isInsertPointPickActive ? 'Click a vertex…' : 'Set Insert Point',
            '      </button>',
            '      <button class="naButtonSecondary" id="naBtnResetInsertPoint"' + (hasCustomInsertPoint ? '' : ' disabled') + '',
            '              title="Return the insertion point to the profile\'s authored origin">Reset</button>',
            '    </div>',
            '  </div>',
            '</div>',

            hasToggles ? [
                '<details class="na-section na-advanced-config" id="naAdvancedConfig"' + (state.isAdvancedConfigOpen ? ' open' : '') + '>',
                '  <summary class="na-advanced-config__summary">Advanced Configuration</summary>',
                '  <div class="na-advanced-config__body">',
                '    <div class="na-advanced-config__group">',
                '      <span class="na-advanced-config__label">Mirror</span>',
                '      <div class="na-toggle-btn-group">',
                Na__Ui__BuildToggleButtonsHtml(toggleDefinitions, toggleStates),
                '      </div>',
                '    </div>',
                '    <div class="na-advanced-config__group">',
                '      <span class="na-advanced-config__label">Rotation</span>',
                '      <div class="na-rotation-pills">',
                Na__Ui__BuildRotationPillsHtml(rotationStep),
                '      </div>',
                '    </div>',
                '  </div>',
                '</details>'
            ].join('') : '',

            '<div class="na-section na-actions-section">',

            // Reverse is baked into the assembly's own transformation at build
            // time (a Z mirror about the plane through its bounds top), so
            // re-applying it to a placed trace would mirror about a different
            // plane and jump the assembly. Disabled rather than hidden, so the
            // reason is readable instead of the control just vanishing.
            '  <button class="naButton naButtonSecondary' + (state.reverseDirection ? ' naButton--reverseActive' : '') + '"',
            '          id="naBtnReverseDirection"' + (isBound ? ' disabled' : ''),
            '          title="' + (isBound
                ? 'Reverse is fixed once a trace is built \u2014 unbind to use it on a new trace.'
                : 'Flip profile direction: rotates 180\u00b0 and flips Z-axis. Hotkey: TAB (works mid-trace and in the Selection preview)') + '">',
            (state.reverseDirection ? '\u21c4 Reversed' : '\u21c4 Reverse'),
            '  </button>',

            // Both act on the MODEL selection, which a running preview has
            // captured \u2014 commit or cancel first, then they mean what they say.
            '  <button class="naButton naButtonSecondary" id="naBtnSwapProfile"' + (isSwapBusy || isPreviewLive ? ' disabled' : '') + '',
            '          title="' + (isPreviewLive
                ? 'Unavailable while previewing \u2014 commit or cancel the preview first.'
                : 'Select a placed Profile Trace in the model, then click this to pick a replacement profile from the Gallery') + '">',
            '\u21c6 Swap Profile',
            '  </button>',

            // Opens the selected trace's profile in the Draw Profile tab, bound
            // to the trace, so the edited outline can be put back on it (Update
            // Trace). Ruby resolves the selection, as for Edit Path.
            '  <button class="naButton naButtonSecondary" id="naBtnOpenDrawEditor"' + (isSwapBusy || isPreviewLive ? ' disabled' : '') + '',
            '          title="' + (isSwapBusy
                ? 'Unavailable while a trace is rebuilding.'
                : isPreviewLive
                    ? 'Unavailable while previewing \u2014 commit or cancel the preview first.'
                    : 'Select a placed Profile Trace in the model, then click this to open its profile in the Draw Profile editor. Edit it, then Update Trace puts it back on the trace.') + '">',
            '\u25f2 Edit Profile',
            '  </button>',

            // The helper rail hugs a corner of the swept solid, so double-clicking
            // into it by hand is close to impossible. That is why the right-click
            // item exists; this is the same item, reachable without first finding
            // a right-clickable spot on the assembly. Deliberately NOT gated on
            // isBound: it acts on the MODEL selection, which is a different thing
            // from a bound trace, so Ruby resolves it and reports the outcome.
            '  <button class="naButton naButtonSecondary" id="naBtnOpenPathEditor"' + (isSwapBusy || isPreviewLive ? ' disabled' : '') + '',
            '          title="' + (isSwapBusy
                ? 'Unavailable while a trace is rebuilding.'
                : isPreviewLive
                    ? 'Unavailable while previewing \u2014 commit or cancel the preview first.'
                    : 'Select a placed Profile Trace in the model, then click this to open its helper path linework with the edges pre-selected. Close the group when done and the profile rebuilds.') + '">',
            '\u270e Edit Path',
            '  </button>',

            isBound && !isPreviewLive ? [
                '<button class="naButton naButtonPrimary" id="naBtnRegenerateTrace"' + (isSwapBusy ? ' disabled' : '') + '',
                '        title="Rebuild the bound trace with the insert point, rotation, mirrors and path offsets set above">',
                'Regenerate Trace',
                '</button>'
            ].join('') : '',

            isPreviewLive ? [
                '<button class="naButton naButtonPrimary" id="naBtnCommitPreview"',
                '        title="Build the profile exactly as previewed. Enter in the viewport does the same.">\u2713 Commit Profile</button>',
                '<button class="naButton naButtonSecondary" id="naBtnCancelPreview"',
                '        title="Leave the preview with nothing built. Esc does the same.">Cancel Preview</button>'
            ].join('') : [
                '<button class="naButton naButtonPrimary" id="naBtnGenerate"',
                '        title="' + (isSelectionMode
                    ? 'Preview the profile along the selected edges. Nothing is built until you Commit.'
                    : 'Start drawing the path in the viewport, with a live preview of the profile.') + '">',
                'Generate Profile',
                '</button>'
            ].join(''),
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Create Profile Form Renderer
    // -------------------------------------------------------------------------

    function Na__Ui__RenderCreateProfileForm(validationResult) {
        var now = new Date();
        var day = String(now.getDate()).padStart(2, '0');
        var months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        var month = months[now.getMonth()];
        var year = now.getFullYear();
        var hours = String(now.getHours()).padStart(2, '0');
        var minutes = String(now.getMinutes()).padStart(2, '0');
        var timestamp = day + '-' + month + '-' + year + '__' + hours + ':' + minutes;

        var summary = 'Selection: ' + (validationResult.faceCount || 0) + ' faces, ' +
                      (validationResult.edgeCount || 0) + ' edges, ' +
                      (validationResult.vertexCount || 0) + ' vertices';

        return [
            '<h2 style="margin:0 0 12px;font-size:15px;">New Profile Details</h2>',
            '<div class="naCreateProfileForm">',
            '  <div class="naValidationSummary">' + summary + '</div>',
            '  <div class="naFormRow">',
            '    <label for="naMetaProfileName">Profile Name</label>',
            '    <input class="naInput" id="naMetaProfileName" type="text" placeholder="e.g. Gutter Box 200x100">',
            '  </div>',
            '  <div class="naFormRow">',
            '    <label for="naMetaDescription">Description</label>',
            '    <textarea class="naTextarea" id="naMetaDescription" rows="2" placeholder="A brief description of this profile shape"></textarea>',
            '  </div>',
            '  <div class="naFormRow">',
            '    <label for="naMetaKeywords">Keywords</label>',
            '    <input class="naInput" id="naMetaKeywords" type="text" placeholder="gutter, box, 200mm (comma separated)">',
            '  </div>',
            '  <div class="naFormRow">',
            '    <label for="naMetaProfileId">Profile ID</label>',
            '    <input class="naInput" id="naMetaProfileId" type="text" placeholder="PRF001_GutterBox__200x100">',
            '  </div>',
            '  <div class="naFormRow">',
            '    <label>Timestamp</label>',
            '    <input class="naInputReadonly" type="text" value="' + timestamp + '" readonly>',
            '  </div>',
            '  <div class="naFormRow">',
            '    <label>Units</label>',
            '    <input class="naInputReadonly" type="text" value="millimetres" readonly>',
            '  </div>',
            '  <div class="naCreateProfileActions">',
            '    <button class="naButtonSuccess" id="naBtnSaveProfile">Save Profile Data File</button>',
            '    <button class="naButtonSecondary" id="naBtnCancelCreateProfile">Cancel</button>',
            '  </div>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Ui__Controls = {
        Na__Ui__RenderControls: Na__Ui__RenderControls,
        Na__Ui__RenderCreateProfileForm: Na__Ui__RenderCreateProfileForm
    };

    // endregion ----------------------------------------------------------------
})();
