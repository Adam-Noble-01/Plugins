(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Configuration State
    // -------------------------------------------------------------------------

    const Na__Ui__Config = {
        profileOptions: [
            { value: '', label: 'Select profile (placeholder)' }
        ],
        pathModeOptions: [
            { value: 'selection', label: 'Use current selection' },
            { value: 'interactive', label: 'Interactive path picking' }
        ],
        defaults: {
            profileKey: '',
            pathMode: 'selection',
            isPreviewEnabled: true
        }
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Profile Options - Setter
    // -------------------------------------------------------------------------

    function Na__Ui__SetProfileOptions(profileOptions) {
        if (!Array.isArray(profileOptions) || profileOptions.length === 0) {
            Na__Ui__Config.profileOptions = [{ value: '', label: 'No enabled profiles found' }];
            return;
        }

        Na__Ui__Config.profileOptions = profileOptions.map(function(profileOption) {
            const label = profileOption.category
                ? profileOption.category + ' :: ' + profileOption.displayName
                : profileOption.displayName;

            return {
                value: profileOption.profileKey,
                label: label
            };
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Ui__Config = Na__Ui__Config;
    window.Na__ProfilePathTracer__Ui__SetProfileOptions = Na__Ui__SetProfileOptions;

    // endregion ----------------------------------------------------------------
})();
