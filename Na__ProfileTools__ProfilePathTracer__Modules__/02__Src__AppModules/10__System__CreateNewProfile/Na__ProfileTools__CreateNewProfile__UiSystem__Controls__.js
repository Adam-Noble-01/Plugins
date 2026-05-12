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

    function Na__Ui__BuildOptionsHtml(options, selectedValue) {
        return options.map(function(option) {
            const isSelected = String(option.value) === String(selectedValue) ? ' selected' : '';
            return '<option value="' + option.value + '"' + isSelected + '>' + option.label + '</option>';
        }).join('');
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

        return [
            '<div class="na-section na-section--controls">',

            '  <div class="naFormRow">',
            '    <label for="naProfileSourceModeSelect">Profile Source</label>',
            '    <select class="naSelect" id="naProfileSourceModeSelect">',
            Na__Ui__BuildOptionsHtml(config.profileSourceModeOptions, profileSourceModeValue),
            '    </select>',
            '  </div>',

            '  <div class="naFormRow">',
            '    <label for="naProfileSelect">Profile</label>',
            '    <select class="naSelect" id="naProfileSelect">',
            Na__Ui__BuildOptionsHtml(config.profileOptions, profileValue),
            '    </select>',
            '  </div>',

            '<div class="naSceneSourceWrap' + (isSceneMode ? '' : ' naSceneSourceWrap--hidden') + '">',
            '  <div class="naSceneStatus ' + sceneReadyClass + '">' + sceneHint + ': ' + sceneProfileName + '</div>',
            '  <div class="naSceneActions">',
            '    <button class="naButton" id="naBtnPickSceneProfile">Pick Scene Profile</button>',
            '    <button class="naButton naButtonSecondary" id="naBtnClearSceneProfile">Clear</button>',
            '  </div>',
            '</div>',

            '  <div class="naFormRow">',
            '    <label for="naPathModeSelect">Path Mode</label>',
            '    <select class="naSelect" id="naPathModeSelect">',
            Na__Ui__BuildOptionsHtml(config.pathModeOptions, pathModeValue),
            '    </select>',
            '  </div>',

            '</div>',

            '<div class="na-section na-viewport-section">',
            '  <div class="naViewportWrap">',
            '    <svg class="naViewportSvg" id="naProfileViewportSvg" viewBox="-120 -120 240 240"></svg>',
            '  </div>',
            '</div>',

            hasToggles ? [
                '<details class="na-section na-advanced-config" id="naAdvancedConfig">',
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
