(function() {
    'use strict';
    let na_is_header_reload_bound = false;

    // -------------------------------------------------------------------------
    // REGION | DOM Event Wiring
    // -------------------------------------------------------------------------

    function Na__Ui__AttachEvents(handlers) {
        const profileSelect = document.getElementById('naProfileSelect');
        const pathModeSelect = document.getElementById('naPathModeSelect');
        const previewEnabled = document.getElementById('naPreviewEnabled');
        const btnGenerate = document.getElementById('naBtnGenerate');

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

        var btnCreateProfile = document.getElementById('naBtnCreateProfile');
        if (btnCreateProfile) {
            btnCreateProfile.addEventListener('click', function() {
                handlers.Na__Events__OnCreateProfile();
            });
        }
    }

    function Na__Ui__AttachHeaderEvents(handlers) {
        if (na_is_header_reload_bound) return;

        const btnReloadPlugin = document.getElementById('naBtnReloadPlugin');
        if (!btnReloadPlugin) return;

        btnReloadPlugin.addEventListener('click', function() {
            handlers.Na__Events__OnReloadPlugin();
        });
        na_is_header_reload_bound = true;
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
        Na__Ui__AttachHeaderEvents: Na__Ui__AttachHeaderEvents,
        Na__Ui__AttachCreateProfileFormEvents: Na__Ui__AttachCreateProfileFormEvents
    };

    // endregion ----------------------------------------------------------------
})();
