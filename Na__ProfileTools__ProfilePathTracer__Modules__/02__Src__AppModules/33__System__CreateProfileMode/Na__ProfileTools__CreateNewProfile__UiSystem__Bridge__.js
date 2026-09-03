/* =============================================================================
   NA PROFILE TOOLS - CREATE NEW PROFILE - UI SYSTEM - BRIDGE
   =============================================================================
   FILE       : Na__ProfileTools__CreateNewProfile__UiSystem__Bridge__.js
   NAMESPACE  : window.Na__ProfilePathTracer__Bridge__*
   PURPOSE    : JS -> Ruby bridge calls for the full plugin lifecycle.
                Handles bootstrap, generate, export, save, scene profile,
                and edge materials management.
   ============================================================================= */

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

        const statusRoot = document.getElementById('na-status-message');
        if (statusRoot) {
            statusRoot.textContent = message;
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Core Plugin Bridge Calls
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

        if (typeof window.Na__ProfilePathTracer__ReceiveBootstrap === 'function') {
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
                sceneProfileStatus: { isValid: false, displayName: '', profileKey: '', statusMessage: 'No scene profile selected.' },
                edgeMaterialsStatus: 'failed',
                isBootstrapError: true,
                statusMessage: 'Bootstrap failed: SketchUp bridge callback is unavailable.'
            });
        }
    }

    function Na__ProfilePathTracer__Bridge__Generate(state) {
        if (Na__Bridge__HasCallback('na_profilepathtracer_generate')) {
            window.sketchup.na_profilepathtracer_generate(JSON.stringify(state || {}));
            return;
        }

        if (typeof window.Na__ProfilePathTracer__ReceiveGenerateResult === 'function') {
            window.Na__ProfilePathTracer__ReceiveGenerateResult({
                isStarted: false,
                statusMessage: 'SketchUp bridge not available (generate fallback response).'
            });
        }
    }

    // Pushed on every Reverse toggle, not just at Generate, so an interactive
    // trace that is already running can flip its preview in place.
    function Na__ProfilePathTracer__Bridge__SetReverseDirection(reverseDirection) {
        if (Na__Bridge__HasCallback('na_profilepathtracer_set_reverse_direction')) {
            window.sketchup.na_profilepathtracer_set_reverse_direction(
                JSON.stringify({ reverseDirection: reverseDirection === true })
            );
        }
    }

    function Na__ProfilePathTracer__Bridge__ValidateForExport() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_validate_for_export')) {
            Na__Bridge__SetStatus('Validating selection for export...');
            window.sketchup.na_profilepathtracer_validate_for_export();
            return;
        }

        if (typeof window.Na__ProfilePathTracer__ReceiveExportValidation === 'function') {
            window.Na__ProfilePathTracer__ReceiveExportValidation({
                isValid: false,
                reason: 'SketchUp bridge not available (export validation fallback).'
            });
        }
    }

    function Na__ProfilePathTracer__Bridge__SaveProfile(metaFields) {
        if (Na__Bridge__HasCallback('na_profilepathtracer_save_profile')) {
            Na__Bridge__SetStatus('Saving profile data...');
            window.sketchup.na_profilepathtracer_save_profile(JSON.stringify(metaFields || {}));
            return;
        }

        if (typeof window.Na__ProfilePathTracer__ReceiveSaveProfileResult === 'function') {
            window.Na__ProfilePathTracer__ReceiveSaveProfileResult({
                isSaved: false,
                reason: 'SketchUp bridge not available (save profile fallback).',
                statusMessage: 'SketchUp bridge not available.'
            });
        }
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
    // REGION | Edge Materials Bridge Calls (Settings)
    // -------------------------------------------------------------------------

    function Na__ProfilePathTracer__Bridge__RefreshEdgeMaterials() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_refresh_edge_materials')) {
            Na__Bridge__SetStatus('Refreshing edge materials from URL...');
            window.sketchup.na_profilepathtracer_refresh_edge_materials();
            return;
        }
        Na__Bridge__SetStatus('Refresh edge materials callback is not available.');
    }

    function Na__ProfilePathTracer__Bridge__PurgeEdgeMaterialsCache() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_purge_edge_materials_cache')) {
            Na__Bridge__SetStatus('Purging edge materials cache...');
            window.sketchup.na_profilepathtracer_purge_edge_materials_cache();
            return;
        }
        Na__Bridge__SetStatus('Purge edge materials cache callback is not available.');
    }

    function Na__ProfilePathTracer__Bridge__ReloadPlugin() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_reload_plugin')) {
            Na__Bridge__SetStatus('Reloading plugin files...');
            window.sketchup.na_profilepathtracer_reload_plugin();
            return;
        }
        Na__Bridge__SetStatus('Reload callback is not available.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Edit Path Bridge Call
    // -------------------------------------------------------------------------

    // Same Ruby callback the right-click item and the Settings button already
    // use, so the Apply Profile button is a third door onto one behaviour rather
    // than a second implementation of it. Ruby owns resolving the trace from the
    // model selection and reports back through the status bar — nothing is
    // decided here, because this side cannot see what is selected in the model.
    function Na__ProfilePathTracer__Bridge__OpenPathEditor() {
        if (Na__Bridge__HasCallback('na_profilepathtracer_open_path_editor')) {
            Na__Bridge__SetStatus('Opening the selected trace path for editing...');
            window.sketchup.na_profilepathtracer_open_path_editor();
            return;
        }
        Na__Bridge__SetStatus('Open path callback is not available.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__Bridge__RequestBootstrap        = Na__ProfilePathTracer__Bridge__RequestBootstrap;
    window.Na__ProfilePathTracer__Bridge__Generate                = Na__ProfilePathTracer__Bridge__Generate;
    window.Na__ProfilePathTracer__Bridge__SetReverseDirection     = Na__ProfilePathTracer__Bridge__SetReverseDirection;
    window.Na__ProfilePathTracer__Bridge__ValidateForExport       = Na__ProfilePathTracer__Bridge__ValidateForExport;
    window.Na__ProfilePathTracer__Bridge__SaveProfile             = Na__ProfilePathTracer__Bridge__SaveProfile;
    window.Na__ProfilePathTracer__Bridge__PickSceneProfile        = Na__ProfilePathTracer__Bridge__PickSceneProfile;
    window.Na__ProfilePathTracer__Bridge__ClearSceneProfile       = Na__ProfilePathTracer__Bridge__ClearSceneProfile;
    window.Na__ProfilePathTracer__Bridge__RequestSceneProfileStatus = Na__ProfilePathTracer__Bridge__RequestSceneProfileStatus;
    window.Na__ProfilePathTracer__Bridge__RefreshEdgeMaterials    = Na__ProfilePathTracer__Bridge__RefreshEdgeMaterials;
    window.Na__ProfilePathTracer__Bridge__PurgeEdgeMaterialsCache = Na__ProfilePathTracer__Bridge__PurgeEdgeMaterialsCache;
    window.Na__ProfilePathTracer__Bridge__ReloadPlugin            = Na__ProfilePathTracer__Bridge__ReloadPlugin;
    window.Na__ProfilePathTracer__Bridge__OpenPathEditor          = Na__ProfilePathTracer__Bridge__OpenPathEditor;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        Na__ProfilePathTracer__Bridge__RequestBootstrap();
    });

    // endregion ----------------------------------------------------------------
})();
