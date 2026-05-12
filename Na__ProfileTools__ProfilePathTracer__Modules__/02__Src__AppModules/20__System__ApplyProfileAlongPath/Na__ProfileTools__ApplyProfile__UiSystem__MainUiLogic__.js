/* =============================================================================
   NA PROFILE TOOLS - APPLY PROFILE - UI SYSTEM - MAIN UI LOGIC
   =============================================================================
   FILE       : Na__ProfileTools__ApplyProfile__UiSystem__MainUiLogic__.js
   NAMESPACE  : window.Na__ProfilePathTracer__ReceiveBootstrap, etc.
   PURPOSE    : Apply Profile tab state management, viewport rendering,
                and Ruby->JS receive handlers for the full plugin.
   ============================================================================= */

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | UI State
    // -------------------------------------------------------------------------

    const Na__UiState = {
        profileKey: '',
        profileSourceMode: 'library',
        pathMode: 'interactive',
        rotationStep: 0,
        isPreviewEnabled: true,
        toggleDefinitions: {},
        toggleStates: {},
        profiles: {},
        sceneProfileStatus: {
            isValid: false,
            displayName: '',
            profileKey: '',
            statusMessage: 'No scene profile selected.'
        },
        edgeMaterialsStatus: 'pending',
        lastGeneratePayload: null,
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function Na__Ui__SetStatus(message) {
        const statusEl = document.getElementById('na-status-message');
        if (statusEl) statusEl.textContent = message || '';

        const statusBar = document.getElementById('na-status-bar');
        if (statusBar) {
            statusBar.classList.toggle('na-hidden', !message);
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
        if (Na__UiState.profileSourceMode === 'scene' && Na__UiState.sceneProfileStatus && Na__UiState.sceneProfileStatus.isValid === true) {
            var sceneProfileKey = Na__UiState.sceneProfileStatus.profileKey || '';
            if (sceneProfileKey && Na__UiState.profiles[sceneProfileKey]) {
                return Na__UiState.profiles[sceneProfileKey];
            }
        }
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
        const svgGen = window.Na__ProfilePathTracer__Viewport__SvgGenerator;
        if (!svgGen) return;

        const previewResult = svgGen.Na__Svg__GenerateProfile(selectedProfile, {
            toggleStates: Na__UiState.toggleStates,
            rotationStep: Na__UiState.rotationStep
        });

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
            profileSourceMode: Na__UiState.profileSourceMode,
            pathMode: Na__UiState.pathMode,
            rotationStep: Na__UiState.rotationStep,
            isPreviewEnabled: Na__UiState.isPreviewEnabled,
            toggleStates: Na__UiState.toggleStates
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Event Handlers
    // -------------------------------------------------------------------------

    const Na__UiEventHandlers = {
        Na__Events__OnProfileSourceModeChange: function(profileSourceMode) {
            Na__UiState.profileSourceMode = profileSourceMode || 'library';
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Profile source mode: ' + Na__UiState.profileSourceMode);
            if (Na__UiState.profileSourceMode === 'scene' && window.Na__ProfilePathTracer__Bridge__RequestSceneProfileStatus) {
                window.Na__ProfilePathTracer__Bridge__RequestSceneProfileStatus();
            }
        },
        Na__Events__OnProfileChange: function(profileKey) {
            Na__UiState.profileKey = profileKey;
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Profile selected: ' + (profileKey || '[none]'));
        },
        Na__Events__OnPathModeChange: function(pathMode) {
            Na__UiState.pathMode = pathMode;
            Na__Ui__SetStatus('Path mode changed: ' + pathMode);
        },
        Na__Events__OnRotateToStep: function(step) {
            Na__UiState.rotationStep = Math.max(0, Math.min(3, Number(step) || 0));
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Rotation set to ' + (Na__UiState.rotationStep * 90) + ' deg');
        },
        Na__Events__OnToggleChange: function(toggleKey, isEnabled) {
            if (!toggleKey) return;
            Na__UiState.toggleStates[toggleKey] = isEnabled;
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Toggle: ' + toggleKey + ' = ' + (isEnabled ? 'ON' : 'OFF'));
        },
        Na__Events__OnGenerate: function() {
            if (Na__UiState.profileSourceMode === 'scene' && Na__UiState.sceneProfileStatus.isValid !== true) {
                Na__Ui__SetStatus('Pick a scene profile source before generating.');
                return;
            }
            Na__UiState.lastGeneratePayload = Na__Ui__BuildGeneratePayload();
            if (window.Na__ProfilePathTracer__Bridge__Generate) {
                window.Na__ProfilePathTracer__Bridge__Generate(Na__UiState.lastGeneratePayload);
            }
        },
        Na__Events__OnPickSceneProfile: function() {
            if (window.Na__ProfilePathTracer__Bridge__PickSceneProfile) {
                window.Na__ProfilePathTracer__Bridge__PickSceneProfile();
            }
        },
        Na__Events__OnClearSceneProfile: function() {
            if (window.Na__ProfilePathTracer__Bridge__ClearSceneProfile) {
                window.Na__ProfilePathTracer__Bridge__ClearSceneProfile();
            }
        },
        Na__Events__OnReloadPlugin: function() {
            if (window.Na__ProfilePathTracer__Bridge__ReloadPlugin) {
                window.Na__ProfilePathTracer__Bridge__ReloadPlugin();
            }
        }
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Panel Rendering
    // -------------------------------------------------------------------------

    function Na__Ui__Render() {
        const controlsRoot = document.getElementById('naApplyProfileTabBody');
        if (!controlsRoot) return;

        controlsRoot.innerHTML = window.Na__ProfilePathTracer__Ui__Controls.Na__Ui__RenderControls(Na__UiState);
        window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachEvents(Na__UiEventHandlers);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Lifecycle (mount / unmount contract)
    // -------------------------------------------------------------------------

    function na_mount() {
        Na__Ui__Render();
        Na__Ui__RenderProfilePreview();
    }

    function na_unmount() {
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

            if (typeof window.Na__ProfilePathTracer__Ui__SetProfileOptions === 'function') {
                window.Na__ProfilePathTracer__Ui__SetProfileOptions(profileOptions);
            }

            Na__UiState.profiles = profileMap;
            Na__UiState.profileKey = payload.profileKey || '';
            Na__UiState.profileSourceMode = payload.profileSourceMode || 'library';
            Na__UiState.pathMode = payload.pathMode || 'interactive';
            Na__UiState.rotationStep = Number(payload.rotationStep || 0) % 4;
            Na__UiState.isPreviewEnabled = payload.isPreviewEnabled !== false;
            Na__UiState.toggleDefinitions = payload.toggleDefinitions || {};
            Na__UiState.edgeMaterialsStatus = payload.edgeMaterialsStatus || 'pending';
            Na__UiState.sceneProfileStatus = payload.sceneProfileStatus || Na__UiState.sceneProfileStatus;

            if (Na__UiState.sceneProfileStatus && Na__UiState.sceneProfileStatus.isValid === true && Na__UiState.sceneProfileStatus.profileData) {
                Na__UiState.profiles[Na__UiState.sceneProfileStatus.profileData.profileKey] = Na__UiState.sceneProfileStatus.profileData;
                Na__UiState.sceneProfileStatus.profileKey = Na__UiState.sceneProfileStatus.profileData.profileKey;
            }

            var defaultToggleStates = payload.toggleStates || {};
            var nextToggleStates = {};
            Object.keys(Na__UiState.toggleDefinitions || {}).forEach(function(toggleKey) {
                nextToggleStates[toggleKey] = Object.prototype.hasOwnProperty.call(defaultToggleStates, toggleKey) ?
                    defaultToggleStates[toggleKey] === true : false;
            });
            Na__UiState.toggleStates = nextToggleStates;

            if (window.Na__ProfilePathTracer__Ui__Config) {
                window.Na__ProfilePathTracer__Ui__Config.toggleDefinitions = Na__UiState.toggleDefinitions;
                window.Na__ProfilePathTracer__Ui__Config.defaults.toggleStates = Na__UiState.toggleStates;
            }

            if (payload.isBootstrapError) {
                bootstrapStatusMessage = payload.statusMessage || 'Bootstrap failed.';
            } else if (!hasProfileOptions) {
                bootstrapStatusMessage = payload.statusMessage || 'Bootstrap returned no enabled profiles.';
            } else if (Na__UiState.edgeMaterialsStatus === 'failed') {
                bootstrapStatusMessage = 'Edge materials unavailable — check internet connection. Profile generation will proceed but edge colours will not be applied.';
            } else if (Na__UiState.edgeMaterialsStatus === 'cache_stale') {
                bootstrapStatusMessage = 'Edge materials loaded from cache (offline). Using cached edge colour data.';
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

    function Na__ProfilePathTracer__ReceiveSceneProfileStatus(result) {
        if (!result || typeof result !== 'object') {
            Na__Ui__SetStatus('Scene profile status returned no payload.');
            return;
        }

        Na__UiState.sceneProfileStatus = {
            isValid: result.isValid === true,
            displayName: result.displayName || '',
            profileKey: result.profileKey || '',
            statusMessage: result.statusMessage || ''
        };

        if (Na__UiState.sceneProfileStatus.isValid && result.profileData && result.profileData.profileKey) {
            Na__UiState.profiles[result.profileData.profileKey] = result.profileData;
            Na__UiState.sceneProfileStatus.profileKey = result.profileData.profileKey;
        }

        Na__Ui__Render();
        Na__Ui__RenderProfilePreview();
        if (result.statusMessage) { Na__Ui__SetStatus(result.statusMessage); }
    }

    function Na__ProfilePathTracer__ReceiveEdgeMaterialsStatus(result) {
        if (!result || typeof result !== 'object') return;
        Na__UiState.edgeMaterialsStatus = result.loadStatus || 'pending';
        Na__Ui__SetStatus(result.statusMessage || 'Edge materials status updated.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__ReceiveBootstrap          = Na__ProfilePathTracer__ReceiveBootstrap;
    window.Na__ProfilePathTracer__ReceiveHeadlessResult     = Na__ProfilePathTracer__ReceiveHeadlessResult;
    window.Na__ProfilePathTracer__ReceiveGenerateResult     = Na__ProfilePathTracer__ReceiveGenerateResult;
    window.Na__ProfilePathTracer__ReceiveSceneProfileStatus = Na__ProfilePathTracer__ReceiveSceneProfileStatus;
    window.Na__ProfilePathTracer__ReceiveEdgeMaterialsStatus = Na__ProfilePathTracer__ReceiveEdgeMaterialsStatus;
    window.Na__ProfilePathTracer__Ui__Render                = Na__Ui__Render;
    window.Na__ProfilePathTracer__Ui__SetStatusFromBridge   = Na__Ui__SetStatusFromBridge;

    window.Na__ProfileTools__ApplyProfile__Tab = {
        na_mount: na_mount,
        na_unmount: na_unmount
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        if (window.Na__ProfilePathTracer__Ui__Events && window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachHeaderEvents) {
            window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachHeaderEvents(Na__UiEventHandlers);
        }
    });

    // endregion ----------------------------------------------------------------
})();
