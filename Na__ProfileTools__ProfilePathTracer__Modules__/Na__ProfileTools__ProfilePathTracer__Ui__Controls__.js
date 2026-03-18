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
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Ui__Controls = {
        Na__Ui__RenderControls: Na__Ui__RenderControls
    };

    // endregion ----------------------------------------------------------------
})();
