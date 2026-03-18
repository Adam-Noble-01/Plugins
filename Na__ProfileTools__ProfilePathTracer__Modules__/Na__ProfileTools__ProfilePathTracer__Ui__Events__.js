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
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Ui__Events = {
        Na__Ui__AttachEvents: Na__Ui__AttachEvents
    };

    // endregion ----------------------------------------------------------------
})();
