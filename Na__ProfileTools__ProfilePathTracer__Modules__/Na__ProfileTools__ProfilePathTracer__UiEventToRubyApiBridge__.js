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
            profileSourceMode: 'library',
            pathMode: 'interactive',
            rotationStep: 0,
            isPreviewEnabled: true,
            toggleDefinitions: {},
            toggleStates: {},
            profileOptions: [],
            profilesByKey: {},
            sceneProfileStatus: {
                isValid: false,
                displayName: '',
                profileKey: '',
                statusMessage: 'No scene profile selected.'
            },
            isBootstrapError: true,
            statusMessage: 'Bootstrap failed: SketchUp bridge callback is unavailable.'
        });
    }

    function Na__ProfilePathTracer__Bridge__ReloadPlugin() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_reload_plugin')) {
            Na__Bridge__SetStatus('Reloading plugin files...');
            window.sketchup.na_profilepathtracer_reload_plugin();
            return;
        }

        Na__Bridge__SetStatus('Reload callback is not available.');
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

    function Na__ProfilePathTracer__Bridge__ValidateForExport() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_validate_for_export')) {
            Na__Bridge__SetStatus('Validating selection for export...');
            window.sketchup.na_profilepathtracer_validate_for_export();
            return;
        }

        window.Na__ProfilePathTracer__ReceiveExportValidation({
            isValid: false,
            reason: 'SketchUp bridge not available (export validation fallback).'
        });
    }

    function Na__ProfilePathTracer__Bridge__SaveProfile(metaFields) {
        if (Na__Bridge__HasCallback('na_profilepathtracer_save_profile')) {
            Na__Bridge__SetStatus('Saving profile data...');
            window.sketchup.na_profilepathtracer_save_profile(JSON.stringify(metaFields || {}));
            return;
        }

        window.Na__ProfilePathTracer__ReceiveSaveProfileResult({
            isSaved: false,
            reason: 'SketchUp bridge not available (save profile fallback).',
            statusMessage: 'SketchUp bridge not available.'
        });
    }

    function Na__ProfilePathTracer__Bridge__PickSceneProfile() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_pick_scene_profile')) {
            Na__Bridge__SetStatus('Pick scene profile source in viewport...');
            window.sketchup.na_profilepathtracer_pick_scene_profile();
            return;
        }
        Na__Bridge__SetStatus('Scene profile picker callback is not available.');
    }

    function Na__ProfilePathTracer__Bridge__ClearSceneProfile() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_clear_scene_profile')) {
            window.sketchup.na_profilepathtracer_clear_scene_profile();
            return;
        }
        Na__Bridge__SetStatus('Clear scene profile callback is not available.');
    }

    function Na__ProfilePathTracer__Bridge__RequestSceneProfileStatus() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_request_scene_profile_status')) {
            window.sketchup.na_profilepathtracer_request_scene_profile_status();
            return;
        }
        if (typeof window.Na__ProfilePathTracer__ReceiveSceneProfileStatus === 'function') {
            window.Na__ProfilePathTracer__ReceiveSceneProfileStatus({
                isValid: false,
                displayName: '',
                profileKey: '',
                statusMessage: 'Scene profile status bridge is unavailable.'
            });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Bridge__RequestBootstrap = Na__ProfilePathTracer__Bridge__RequestBootstrap;
    window.Na__ProfilePathTracer__Bridge__ReloadPlugin = Na__ProfilePathTracer__Bridge__ReloadPlugin;
    window.Na__ProfilePathTracer__Bridge__Generate = Na__ProfilePathTracer__Bridge__Generate;
    window.Na__ProfilePathTracer__Bridge__ValidateForExport = Na__ProfilePathTracer__Bridge__ValidateForExport;
    window.Na__ProfilePathTracer__Bridge__SaveProfile = Na__ProfilePathTracer__Bridge__SaveProfile;
    window.Na__ProfilePathTracer__Bridge__PickSceneProfile = Na__ProfilePathTracer__Bridge__PickSceneProfile;
    window.Na__ProfilePathTracer__Bridge__ClearSceneProfile = Na__ProfilePathTracer__Bridge__ClearSceneProfile;
    window.Na__ProfilePathTracer__Bridge__RequestSceneProfileStatus = Na__ProfilePathTracer__Bridge__RequestSceneProfileStatus;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        Na__ProfilePathTracer__Bridge__RequestBootstrap();
    });

    // endregion ----------------------------------------------------------------
})();
