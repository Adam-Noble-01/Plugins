(function() {
    'use strict';

    const NA_BRIDGE_BOOTSTRAP_MAX_RETRIES = 5;
    const NA_BRIDGE_BOOTSTRAP_RETRY_DELAY_MS = 120;

    // -------------------------------------------------------------------------
    // REGION | Bridge Availability
    // -------------------------------------------------------------------------

    function Na__Bridge__IsSketchUpAvailable() {
        return !!(window.sketchup);
    }

    function Na__Bridge__HasCallback(callbackName) {
        return Na__Bridge__IsSketchUpAvailable() && typeof window.sketchup[callbackName] === 'function';
    }

    function Na__Bridge__SetStatus(message) {
        if (typeof window.Na__ProfilePathTracer__Ui__SetStatusFromBridge === 'function') {
            window.Na__ProfilePathTracer__Ui__SetStatusFromBridge(message);
            return;
        }

        const statusRoot = document.getElementById('naStatusRoot');
        if (statusRoot) {
            statusRoot.textContent = message;
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Bridge Calls (JS -> Ruby)
    // -------------------------------------------------------------------------

    function Na__ProfilePathTracer__Bridge__RequestBootstrap(retryIndex) {
        const currentRetryIndex = Number.isInteger(retryIndex) ? retryIndex : 0;

        if (Na__Bridge__HasCallback('na_profilepathtracer_request_bootstrap')) {
            Na__Bridge__SetStatus('Requesting bootstrap data from SketchUp...');
            window.sketchup.na_profilepathtracer_request_bootstrap();
            return;
        }

        if (currentRetryIndex < NA_BRIDGE_BOOTSTRAP_MAX_RETRIES) {
            Na__Bridge__SetStatus('SketchUp bridge not ready. Retrying bootstrap...');
            window.setTimeout(function() {
                Na__ProfilePathTracer__Bridge__RequestBootstrap(currentRetryIndex + 1);
            }, NA_BRIDGE_BOOTSTRAP_RETRY_DELAY_MS);
            return;
        }

        window.Na__ProfilePathTracer__ReceiveBootstrap({
            profileKey: '',
            pathMode: 'selection',
            isPreviewEnabled: true,
            profileOptions: [],
            profilesByKey: {},
            isBootstrapError: true,
            statusMessage: 'Bootstrap failed: SketchUp bridge callback is unavailable.'
        });
    }

    function Na__ProfilePathTracer__Bridge__RunHeadless(state) {
        if (Na__Bridge__HasCallback('na_profilepathtracer_run_headless')) {
            window.sketchup.na_profilepathtracer_run_headless(JSON.stringify(state || {}));
            return;
        }
        window.Na__ProfilePathTracer__ReceiveHeadlessResult({
            isBuilt: false,
            mode: 'headless',
            reason: 'SketchUp bridge not available (fallback response).'
        });
    }

    function Na__ProfilePathTracer__Bridge__Generate(state) {
        if (Na__Bridge__HasCallback('na_profilepathtracer_generate')) {
            window.sketchup.na_profilepathtracer_generate(JSON.stringify(state || {}));
            return;
        }

        window.Na__ProfilePathTracer__ReceiveGenerateResult({
            isStarted: false,
            statusMessage: 'SketchUp bridge not available (generate fallback response).'
        });
    }

    function Na__ProfilePathTracer__Bridge__ActivatePreviewTool(state) {
        if (Na__Bridge__HasCallback('na_profilepathtracer_activate_preview_tool')) {
            window.sketchup.na_profilepathtracer_activate_preview_tool(JSON.stringify(state || {}));
            return;
        }

        window.Na__ProfilePathTracer__ReceiveGenerateResult({
            isStarted: false,
            statusMessage: 'SketchUp bridge not available (preview-tool fallback response).'
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Bridge__RequestBootstrap = Na__ProfilePathTracer__Bridge__RequestBootstrap;
    window.Na__ProfilePathTracer__Bridge__RunHeadless = Na__ProfilePathTracer__Bridge__RunHeadless;
    window.Na__ProfilePathTracer__Bridge__Generate = Na__ProfilePathTracer__Bridge__Generate;
    window.Na__ProfilePathTracer__Bridge__ActivatePreviewTool = Na__ProfilePathTracer__Bridge__ActivatePreviewTool;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        Na__ProfilePathTracer__Bridge__RequestBootstrap();
    });

    // endregion ----------------------------------------------------------------
})();
