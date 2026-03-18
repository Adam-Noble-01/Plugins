(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | UI State
    // -------------------------------------------------------------------------

    const Na__UiState = {
        profileKey: '',
        pathMode: 'selection',
        isPreviewEnabled: true,
        profiles: {},
        lastGeneratePayload: null
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function Na__Ui__SetStatus(message) {
        const statusRoot = document.getElementById('naStatusRoot');
        if (statusRoot) {
            statusRoot.textContent = message;
        }
    }

    function Na__Ui__SetStatusFromBridge(message) {
        Na__Ui__SetStatus(message || 'Bridge status update received.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Profile Selection Helpers
    // -------------------------------------------------------------------------

    function Na__Ui__SelectedProfileRecord() {
        return Na__UiState.profiles[Na__UiState.profileKey] || null;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Viewport Preview Rendering
    // -------------------------------------------------------------------------

    function Na__Ui__RenderProfilePreview() {
        const viewportSvg = document.getElementById('naProfileViewportSvg');
        if (!viewportSvg) return;

        if (!Na__UiState.isPreviewEnabled) {
            viewportSvg.innerHTML = '';
            viewportSvg.setAttribute('viewBox', '-120 -120 240 240');
            return;
        }

        const selectedProfile = Na__Ui__SelectedProfileRecord();
        const previewResult = window.Na__ProfilePathTracer__Viewport__SvgGenerator.Na__Svg__GenerateProfile(selectedProfile);

        viewportSvg.setAttribute('viewBox', previewResult.viewBox || '-120 -120 240 240');
        viewportSvg.innerHTML = previewResult.svg || '';

        if (!previewResult.isValid) {
            Na__Ui__SetStatus('Preview unavailable: ' + previewResult.reason);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Payload Builders
    // -------------------------------------------------------------------------

    function Na__Ui__BuildGeneratePayload() {
        return {
            profileKey: Na__UiState.profileKey,
            pathMode: Na__UiState.pathMode,
            isPreviewEnabled: Na__UiState.isPreviewEnabled
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | UI Rendering + Event Wiring
    // -------------------------------------------------------------------------

    function Na__Ui__Render() {
        const controlsRoot = document.getElementById('naControlsRoot');
        if (!controlsRoot) return;

        controlsRoot.innerHTML = window.Na__ProfilePathTracer__Ui__Controls.Na__Ui__RenderControls(Na__UiState);
        window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachEvents({
            Na__Events__OnProfileChange: function(profileKey) {
                Na__UiState.profileKey = profileKey;
                Na__Ui__RenderProfilePreview();
                Na__Ui__SetStatus('Profile selected: ' + (profileKey || '[none]'));
            },
            Na__Events__OnPathModeChange: function(pathMode) {
                Na__UiState.pathMode = pathMode;
                Na__Ui__SetStatus('Path mode changed: ' + pathMode);
            },
            Na__Events__OnPreviewToggle: function(isEnabled) {
                Na__UiState.isPreviewEnabled = isEnabled;
                Na__Ui__RenderProfilePreview();
                Na__Ui__SetStatus('Preview ' + (isEnabled ? 'enabled' : 'disabled') + '.');
            },
            Na__Events__OnGenerate: function() {
                Na__UiState.lastGeneratePayload = Na__Ui__BuildGeneratePayload();
                if (window.Na__ProfilePathTracer__Bridge__Generate) {
                    window.Na__ProfilePathTracer__Bridge__Generate(Na__UiState.lastGeneratePayload);
                }
            },
            Na__Events__OnRequestBootstrap: function() {
                if (window.Na__ProfilePathTracer__Bridge__RequestBootstrap) {
                    window.Na__ProfilePathTracer__Bridge__RequestBootstrap();
                }
            },
            Na__Events__OnPickPath: function() {
                if (window.Na__ProfilePathTracer__Bridge__ActivatePreviewTool) {
                    window.Na__ProfilePathTracer__Bridge__ActivatePreviewTool(Na__Ui__BuildGeneratePayload());
                } else {
                    Na__Ui__SetStatus('Pick path callback is not available.');
                }
            },
            Na__Events__OnRunHeadless: function() {
                if (window.Na__ProfilePathTracer__Bridge__RunHeadless) {
                    window.Na__ProfilePathTracer__Bridge__RunHeadless(Na__UiState);
                }
            }
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Ruby -> JS Receive Handlers
    // -------------------------------------------------------------------------

    function Na__ProfilePathTracer__ReceiveBootstrap(payload) {
        let hasProfileOptions = false;
        let bootstrapStatusMessage = 'Bootstrap loaded.';

        if (payload && typeof payload === 'object') {
            const profileOptions = Array.isArray(payload.profileOptions) ? payload.profileOptions : [];
            const profileMap = payload.profilesByKey || {};
            hasProfileOptions = profileOptions.length > 0;
            window.Na__ProfilePathTracer__Ui__SetProfileOptions(profileOptions);

            Na__UiState.profiles = profileMap;
            Na__UiState.profileKey = payload.profileKey || '';
            Na__UiState.pathMode = payload.pathMode || 'selection';
            Na__UiState.isPreviewEnabled = payload.isPreviewEnabled !== false;

            if (payload.isBootstrapError) {
                bootstrapStatusMessage = payload.statusMessage || 'Bootstrap failed.';
            } else if (!hasProfileOptions) {
                bootstrapStatusMessage = payload.statusMessage || 'Bootstrap returned no enabled profiles.';
            }
        } else {
            bootstrapStatusMessage = 'Bootstrap failed: invalid payload from Ruby.';
        }

        Na__Ui__Render();
        Na__Ui__RenderProfilePreview();
        Na__Ui__SetStatus(bootstrapStatusMessage);
    }

    function Na__ProfilePathTracer__ReceiveHeadlessResult(result) {
        if (result && result.statusMessage) {
            Na__Ui__SetStatus(result.statusMessage);
        } else {
            Na__Ui__SetStatus('Headless run result received.');
        }
    }

    function Na__ProfilePathTracer__ReceiveGenerateResult(result) {
        if (!result || typeof result !== 'object') {
            Na__Ui__SetStatus('Generate returned no result.');
            return;
        }

        Na__Ui__SetStatus(result.statusMessage || 'Generate callback complete.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__ReceiveBootstrap = Na__ProfilePathTracer__ReceiveBootstrap;
    window.Na__ProfilePathTracer__ReceiveHeadlessResult = Na__ProfilePathTracer__ReceiveHeadlessResult;
    window.Na__ProfilePathTracer__ReceiveGenerateResult = Na__ProfilePathTracer__ReceiveGenerateResult;
    window.Na__ProfilePathTracer__Ui__Render = Na__Ui__Render;
    window.Na__ProfilePathTracer__Ui__SetStatusFromBridge = Na__Ui__SetStatusFromBridge;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        Na__Ui__Render();
    });

    // endregion ----------------------------------------------------------------
})();
