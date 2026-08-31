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
        var activeRecord     = store ? store.Na__Store__GetSelectedRecord() : null;
        var activeName       = activeRecord ? (activeRecord.displayName || activeRecord.profileKey || '') : '';
        var activeHint       = activeName
            ? '<span class="na-active-profile__name">' + activeName + '</span>'
            : '<span class="na-active-profile__hint">No profile selected — choose one in the Gallery.</span>';

        var swapState  = state.swap || null;
        var isBound    = !!(swapState && swapState.isBound);
        var isSwapBusy = !!(swapState && swapState.isBusy);

        return [
            Na__Ui__BuildBoundTraceHtml(swapState),
            Na__Ui__BuildSwapArmedHtml(swapState),

            '<div class="na-section na-section--controls">',

            '  <div class="naFormRow">',
            '    <label>Active Profile</label>',
            '    <div class="na-active-profile" id="naActiveProfileIndicator">',
            activeHint,
            '    </div>',
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
                : 'Flip profile direction: rotates 180\u00b0 and flips Z-axis. Hotkey: TAB (works mid-trace)') + '">',
            (state.reverseDirection ? '\u21c4 Reversed' : '\u21c4 Reverse'),
            '  </button>',

            '  <button class="naButton naButtonSecondary" id="naBtnSwapProfile"' + (isSwapBusy ? ' disabled' : '') + '',
            '          title="Select a placed Profile Trace in the model, then click this to pick a replacement profile from the Gallery">',
            '\u21c6 Swap Profile',
            '  </button>',

            isBound ? [
                '<button class="naButton naButtonPrimary" id="naBtnRegenerateTrace"' + (isSwapBusy ? ' disabled' : '') + '',
                '        title="Rebuild the bound trace with the insert point, rotation and mirrors set above">',
                'Regenerate Trace',
                '</button>'
            ].join('') : '',

            '  <button class="naButton naButtonPrimary" id="naBtnGenerate">Generate Profile</button>',
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
