(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Html Helpers
    // -------------------------------------------------------------------------

    function Na__Ui__BuildOptionsHtml(options, selectedValue) {
        return options.map(function(option) {
            const isSelected = String(option.value) === String(selectedValue) ? ' selected' : '';
            return '<option value="' + option.value + '"' + isSelected + '>' + option.label + '</option>';
        }).join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Controls Renderer
    // -------------------------------------------------------------------------

    function Na__Ui__RenderControls(state) {
        const config = window.Na__ProfilePathTracer__Ui__Config;
        const profileValue = state.profileKey || config.defaults.profileKey;
        const pathModeValue = state.pathMode || config.defaults.pathMode;
        const previewChecked = state.isPreviewEnabled ? ' checked' : '';

        return [
            '<div class="naFormRow">',
            '  <label for="naProfileSelect">Profile</label>',
            '  <select class="naSelect" id="naProfileSelect">',
            Na__Ui__BuildOptionsHtml(config.profileOptions, profileValue),
            '  </select>',
            '</div>',
            '<div class="naFormRow">',
            '  <label for="naPathModeSelect">Path Mode</label>',
            '  <select class="naSelect" id="naPathModeSelect">',
            Na__Ui__BuildOptionsHtml(config.pathModeOptions, pathModeValue),
            '  </select>',
            '</div>',
            '<div class="naFormRow">',
            '  <label for="naPreviewEnabled">Preview</label>',
            '  <input class="naInput" id="naPreviewEnabled" type="checkbox"' + previewChecked + '>',
            '</div>',
            '<div class="naActions">',
            '  <button class="naButton naButtonPrimary" id="naBtnGenerate">Generate</button>',
            '  <button class="naButton" id="naBtnRequestBootstrap">Reload Bootstrap</button>',
            '  <button class="naButton" id="naBtnPickPath">Pick Path</button>',
            '  <button class="naButton" id="naBtnRunHeadless">Run Headless</button>',
            '  <button class="naButton naButtonCreate" id="naBtnCreateProfile">Create New Profile</button>',
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
