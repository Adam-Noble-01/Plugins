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
        lastGeneratePayload: null,
        isCreateProfileFormVisible: false,
        lastExportValidation: null
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
        const previewResult = window.Na__ProfilePathTracer__Viewport__SvgGenerator.Na__Svg__GenerateProfile(selectedProfile, {
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
    // REGION | Create Profile Form Helpers
    // -------------------------------------------------------------------------

    function Na__Ui__ShowCreateProfilePanel(validationResult) {
        var panel = document.getElementById('naCreateProfilePanel');
        var formRoot = document.getElementById('naCreateProfileFormRoot');
        if (!panel || !formRoot) return;

        formRoot.innerHTML = window.Na__ProfilePathTracer__Ui__Controls.Na__Ui__RenderCreateProfileForm(validationResult);
        panel.style.display = '';

        window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachCreateProfileFormEvents({
            Na__Events__OnSaveProfile: function() {
                var profileName = (document.getElementById('naMetaProfileName') || {}).value || '';
                var description = (document.getElementById('naMetaDescription') || {}).value || '';
                var keywordsRaw = (document.getElementById('naMetaKeywords') || {}).value || '';
                var profileId   = (document.getElementById('naMetaProfileId') || {}).value || '';

                var keywords = keywordsRaw.split(',').map(function(k) { return k.trim(); }).filter(function(k) { return k.length > 0; });

                var metaFields = {
                    Meta_ProfileName: profileName,
                    Meta_Description: description,
                    Meta_Keywords: keywords,
                    Meta_ProfileId: profileId
                };

                if (!profileName && !profileId) {
                    Na__Ui__SetStatus('Profile Name or Profile ID is required.');
                    return;
                }

                Na__Ui__SetStatus('Saving profile...');
                if (window.Na__ProfilePathTracer__Bridge__SaveProfile) {
                    window.Na__ProfilePathTracer__Bridge__SaveProfile(metaFields);
                }
            },
            Na__Events__OnCancelCreateProfile: function() {
                Na__Ui__HideCreateProfilePanel();
                Na__Ui__SetStatus('Create profile cancelled.');
            }
        });

        Na__UiState.isCreateProfileFormVisible = true;
    }

    function Na__Ui__HideCreateProfilePanel() {
        var panel = document.getElementById('naCreateProfilePanel');
        if (panel) panel.style.display = 'none';
        Na__UiState.isCreateProfileFormVisible = false;
        Na__Ui__RenderProfilePreview();
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

    function Na__Ui__BuildUnifiedPreviewRecordFromPoints(points) {
        var sourcePoints = Array.isArray(points) ? points : [];
        if (sourcePoints.length < 3) return null;

        var vertices = sourcePoints.map(function(point, index) {
            return {
                VertexId: 'V' + String(index + 1).padStart(3, '0'),
                PosY_mm: Number(point[0]),
                PosZ_mm: Number(point[1])
            };
        });

        var edges = vertices.map(function(vertex, index) {
            var nextIndex = (index + 1) % vertices.length;
            return {
                EdgeId: 'E' + String(index + 1).padStart(3, '0'),
                StartVertex: vertex.VertexId,
                EndVertex: vertices[nextIndex].VertexId
            };
        });

        var meshEdges = edges.map(function(edge) {
            return {
                EdgeId: edge.EdgeId,
                StartVertex: edge.StartVertex,
                EndVertex: edge.EndVertex,
                IsSoft: false,
                IsSmooth: false,
                IsHidden: false,
                CastsShadows: true,
                EdgeMaterialName: '',
                EdgeColourId: '',
                EdgeColourHex: ''
            };
        });

        return {
            profileData: {
                type: 'na_unified_asset',
                assetData: {
                    meta: {},
                    Na__Asset__Metadata: {},
                    Na__Asset__Profile2D: {
                        Na__Geometry__Vertices: vertices,
                        Na__Geometry__Edges: edges,
                        Na__Geometry__Faces: [{
                            FaceId: 'F001',
                            OuterLoopVertices: vertices.map(function(vertex) { return vertex.VertexId; })
                        }]
                    },
                    Na__Asset__Mesh3D: {
                        Na__Geometry__Edges: meshEdges
                    }
                }
            }
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | UI Rendering + Event Wiring
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
        Na__Events__OnRotateProfile: function() {
            Na__UiState.rotationStep = (Number(Na__UiState.rotationStep) + 1) % 4;
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Rotation set to ' + (Na__UiState.rotationStep * 90) + ' deg');
        },
        Na__Events__OnPreviewToggle: function(isEnabled) {
            Na__UiState.isPreviewEnabled = isEnabled;
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Preview ' + (isEnabled ? 'enabled' : 'disabled') + '.');
        },
        Na__Events__OnToggleChange: function(toggleKey, isEnabled) {
            if (!toggleKey) return;
            Na__UiState.toggleStates[toggleKey] = isEnabled;
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Toggle updated: ' + toggleKey + ' = ' + (isEnabled ? 'ON' : 'OFF'));
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
        },
        Na__Events__OnCreateProfile: function() {
            Na__Ui__SetStatus('Validating selection for profile export...');
            if (window.Na__ProfilePathTracer__Bridge__ValidateForExport) {
                window.Na__ProfilePathTracer__Bridge__ValidateForExport();
            } else {
                Na__Ui__SetStatus('Export validation bridge is not available.');
            }
        }
    };

    function Na__Ui__Render() {
        const controlsRoot = document.getElementById('naControlsRoot');
        if (!controlsRoot) return;

        controlsRoot.innerHTML = window.Na__ProfilePathTracer__Ui__Controls.Na__Ui__RenderControls(Na__UiState);
        window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachEvents(Na__UiEventHandlers);
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
            Na__UiState.profileSourceMode = payload.profileSourceMode || 'library';
            Na__UiState.pathMode = payload.pathMode || 'interactive';
            Na__UiState.rotationStep = Number(payload.rotationStep || 0) % 4;
            Na__UiState.isPreviewEnabled = payload.isPreviewEnabled !== false;
            Na__UiState.toggleDefinitions = payload.toggleDefinitions || {};
            Na__UiState.sceneProfileStatus = payload.sceneProfileStatus || Na__UiState.sceneProfileStatus;
            if (Na__UiState.sceneProfileStatus && Na__UiState.sceneProfileStatus.isValid === true && Na__UiState.sceneProfileStatus.profileData) {
                Na__UiState.profiles[Na__UiState.sceneProfileStatus.profileData.profileKey] = Na__UiState.sceneProfileStatus.profileData;
                Na__UiState.sceneProfileStatus.profileKey = Na__UiState.sceneProfileStatus.profileData.profileKey;
            }

            var defaultToggleStates = payload.toggleStates || {};
            var nextToggleStates = {};
            Object.keys(Na__UiState.toggleDefinitions || {}).forEach(function(toggleKey) {
                if (Object.prototype.hasOwnProperty.call(defaultToggleStates, toggleKey)) {
                    nextToggleStates[toggleKey] = defaultToggleStates[toggleKey] === true;
                } else {
                    nextToggleStates[toggleKey] = false;
                }
            });
            Na__UiState.toggleStates = nextToggleStates;

            window.Na__ProfilePathTracer__Ui__Config.toggleDefinitions = Na__UiState.toggleDefinitions;
            window.Na__ProfilePathTracer__Ui__Config.defaults.toggleStates = Na__UiState.toggleStates;

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
        if (result.statusMessage) {
            Na__Ui__SetStatus(result.statusMessage);
        }
    }

    function Na__ProfilePathTracer__ReceiveExportValidation(result) {
        if (!result || typeof result !== 'object') {
            Na__Ui__SetStatus('Export validation returned no result.');
            return;
        }

        if (result.isPendingOrigin === true) {
            Na__Ui__SetStatus(result.statusMessage || 'Click in model to place 00__OriginPoint first.');
            return;
        }

        if (!result.isValid) {
            Na__Ui__SetStatus(result.statusMessage || ('Cannot create profile: ' + (result.reason || 'Unknown error.')));
            return;
        }

        Na__UiState.lastExportValidation = result;

        if (Array.isArray(result.previewPoints) && result.previewPoints.length >= 2) {
            var exportPreviewRecord = Na__Ui__BuildUnifiedPreviewRecordFromPoints(result.previewPoints);
            var viewportSvg = document.getElementById('naProfileViewportSvg');
            if (viewportSvg && exportPreviewRecord) {
                    var previewResult = window.Na__ProfilePathTracer__Viewport__SvgGenerator.Na__Svg__GenerateProfile(exportPreviewRecord, {
                        toggleStates: Na__UiState.toggleStates,
                        rotationStep: Na__UiState.rotationStep
                    });
                viewportSvg.setAttribute('viewBox', previewResult.viewBox || '-120 -120 240 240');
                viewportSvg.innerHTML = previewResult.svg || '';
            }
        }

        Na__Ui__ShowCreateProfilePanel(result);
        Na__Ui__SetStatus(result.statusMessage || 'Origin point set. Fill in profile details, then click Save Profile Data File.');
    }

    function Na__ProfilePathTracer__ReceiveSaveProfileResult(result) {
        if (!result || typeof result !== 'object') {
            Na__Ui__SetStatus('Save returned no result.');
            return;
        }

        if (result.isPending === true) {
            Na__Ui__SetStatus(result.statusMessage || 'Click in model to place the origin helper point.');
            return;
        }

        if (result.isSaved) {
            Na__Ui__HideCreateProfilePanel();
            Na__Ui__SetStatus(result.statusMessage || 'Profile saved successfully.');
        } else {
            Na__Ui__SetStatus(result.statusMessage || 'Profile save failed.');
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfilePathTracer__ReceiveBootstrap = Na__ProfilePathTracer__ReceiveBootstrap;
    window.Na__ProfilePathTracer__ReceiveHeadlessResult = Na__ProfilePathTracer__ReceiveHeadlessResult;
    window.Na__ProfilePathTracer__ReceiveGenerateResult = Na__ProfilePathTracer__ReceiveGenerateResult;
    window.Na__ProfilePathTracer__ReceiveSceneProfileStatus = Na__ProfilePathTracer__ReceiveSceneProfileStatus;
    window.Na__ProfilePathTracer__ReceiveExportValidation = Na__ProfilePathTracer__ReceiveExportValidation;
    window.Na__ProfilePathTracer__ReceiveSaveProfileResult = Na__ProfilePathTracer__ReceiveSaveProfileResult;
    window.Na__ProfilePathTracer__Ui__Render = Na__Ui__Render;
    window.Na__ProfilePathTracer__Ui__SetStatusFromBridge = Na__Ui__SetStatusFromBridge;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Init
    // -------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachHeaderEvents(Na__UiEventHandlers);
        Na__Ui__Render();
    });

    // endregion ----------------------------------------------------------------
})();
