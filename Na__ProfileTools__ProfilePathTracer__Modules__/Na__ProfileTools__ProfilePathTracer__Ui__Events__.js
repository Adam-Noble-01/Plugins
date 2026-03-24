(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | DOM Event Wiring
    // -------------------------------------------------------------------------

    function Na__Ui__AttachEvents(handlers) {
        const profileSelect = document.getElementById('naProfileSelect');
        const pathModeSelect = document.getElementById('naPathModeSelect');
        const previewEnabled = document.getElementById('naPreviewEnabled');
        const btnGenerate = document.getElementById('naBtnGenerate');
        const btnBootstrap = document.getElementById('naBtnRequestBootstrap');
        const btnPickPath = document.getElementById('naBtnPickPath');
        const btnRunHeadless = document.getElementById('naBtnRunHeadless');

        if (profileSelect) {
            profileSelect.addEventListener('change', function() {
                handlers.Na__Events__OnProfileChange(profileSelect.value);
            });
        }

        if (pathModeSelect) {
            pathModeSelect.addEventListener('change', function() {
                handlers.Na__Events__OnPathModeChange(pathModeSelect.value);
            });
        }

        if (previewEnabled) {
            previewEnabled.addEventListener('change', function() {
                handlers.Na__Events__OnPreviewToggle(!!previewEnabled.checked);
            });
        }

        var toggleInputs = document.querySelectorAll('.naToggleInput[data-na-toggle-key]');
        if (toggleInputs && toggleInputs.length > 0) {
            Array.prototype.forEach.call(toggleInputs, function(toggleInput) {
                toggleInput.addEventListener('change', function() {
                    var toggleKey = toggleInput.getAttribute('data-na-toggle-key') || '';
                    handlers.Na__Events__OnToggleChange(toggleKey, !!toggleInput.checked);
                });
            });
        }

        if (btnGenerate) {
            btnGenerate.addEventListener('click', function() {
                handlers.Na__Events__OnGenerate();
            });
        }

        if (btnBootstrap) {
            btnBootstrap.addEventListener('click', function() {
                handlers.Na__Events__OnRequestBootstrap();
            });
        }

        if (btnPickPath) {
            btnPickPath.addEventListener('click', function() {
                handlers.Na__Events__OnPickPath();
            });
        }

        if (btnRunHeadless) {
            btnRunHeadless.addEventListener('click', function() {
                handlers.Na__Events__OnRunHeadless();
            });
        }

        var btnCreateProfile = document.getElementById('naBtnCreateProfile');
        if (btnCreateProfile) {
            btnCreateProfile.addEventListener('click', function() {
                handlers.Na__Events__OnCreateProfile();
            });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Create Profile Form Event Wiring
    // -------------------------------------------------------------------------

    function Na__Ui__AttachCreateProfileFormEvents(handlers) {
        var btnSave = document.getElementById('naBtnSaveProfile');
        var btnCancel = document.getElementById('naBtnCancelCreateProfile');

        if (btnSave) {
            btnSave.addEventListener('click', function() {
                handlers.Na__Events__OnSaveProfile();
            });
        }

        if (btnCancel) {
            btnCancel.addEventListener('click', function() {
                handlers.Na__Events__OnCancelCreateProfile();
            });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Ui__Events = {
        Na__Ui__AttachEvents: Na__Ui__AttachEvents,
        Na__Ui__AttachCreateProfileFormEvents: Na__Ui__AttachCreateProfileFormEvents
    };

    // endregion ----------------------------------------------------------------
})();
