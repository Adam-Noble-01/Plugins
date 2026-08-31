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
        reverseDirection: false,
        // { y, z } in the profile's authored PosY_mm / PosZ_mm space, or null to
        // use the profile's own origin. Set by picking a vertex in the 2D preview.
        originOffset: null,
        isInsertPointPickActive: false,
        // The whole controls panel is re-rendered on every change, which would
        // otherwise snap the Advanced Configuration disclosure shut under the
        // rotation pill or mirror toggle the user just clicked.
        isAdvancedConfigOpen: false,
        // Mirrors the running Na__PathSelectionTool. Only true while a trace is
        // live, which is the only time TAB is ours to take from focus traversal.
        isInteractiveToolActive: false,
        previewSourcePoints: [],
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
        // Mirror of Na__ProfileTools__SwapController, refreshed on every render.
        // When a trace is bound, this tab's controls edit THAT placed assembly
        // and Regenerate Trace applies them; otherwise it behaves exactly as
        // before and Generate Profile builds a new one.
        swap: null,
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
        var store = window.Na__ProfileTools__ProfileStore;
        if (store && store.Na__Store__GetSelectedRecord()) {
            return store.Na__Store__GetSelectedRecord();
        }
        return Na__UiState.profiles[Na__UiState.profileKey] || null;
    }

    function Na__Ui__UpdateActiveProfileIndicator() {
        var indicatorEl = document.getElementById('naActiveProfileIndicator');
        if (!indicatorEl) return;
        var store  = window.Na__ProfileTools__ProfileStore;
        var record = store ? store.Na__Store__GetSelectedRecord() : null;
        if (record) {
            var name = record.displayName || record.profileKey || '';
            indicatorEl.innerHTML = '<span class="na-active-profile__name">' + name + '</span>';
        } else {
            indicatorEl.innerHTML = '<span class="na-active-profile__hint">No profile selected — choose one in the Gallery.</span>';
        }
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
            rotationStep: Na__UiState.rotationStep,
            reverseDirection: Na__UiState.reverseDirection,
            originOffset: Na__UiState.originOffset,
            showVertexHandles: Na__UiState.isInsertPointPickActive
        });

        // Cached in the profile's authored coordinates so a picked handle resolves
        // to an absolute datum rather than compounding with the current offset.
        Na__UiState.previewSourcePoints = previewResult.sourcePoints || [];

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

    function Na__Ui__ResolveActiveProfileKey() {
        var store = window.Na__ProfileTools__ProfileStore;
        if (store) {
            var storeKey = store.Na__Store__GetSelectedKey();
            if (storeKey) return storeKey;
        }
        return Na__UiState.profileKey || '';
    }

    function Na__Ui__SyncProfileKeyFromStore() {
        var store = window.Na__ProfileTools__ProfileStore;
        if (!store) return;

        var selectedKey = store.Na__Store__GetSelectedKey();
        if (!selectedKey) return;

        Na__UiState.profileKey = selectedKey;
        var record = store.Na__Store__GetSelectedRecord();
        if (record) {
            Na__UiState.profiles[selectedKey] = record;
        }
    }

    function Na__Ui__BuildGeneratePayload() {
        return {
            profileKey: Na__Ui__ResolveActiveProfileKey(),
            profileSourceMode: Na__UiState.profileSourceMode,
            pathMode: Na__UiState.pathMode,
            rotationStep: Na__UiState.rotationStep,
            isPreviewEnabled: Na__UiState.isPreviewEnabled,
            reverseDirection: Na__UiState.reverseDirection,
            originOffset: Na__UiState.originOffset,
            toggleStates: Na__UiState.toggleStates
        };
    }

    // A datum picked on one profile means nothing on another, so switching the
    // active profile drops the offset instead of silently re-datuming the new one.
    function Na__Ui__ClearInsertPointState() {
        Na__UiState.originOffset = null;
        Na__UiState.isInsertPointPickActive = false;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Bound Trace Helpers (profile hot swap)
    // -------------------------------------------------------------------------

    function Na__Ui__SwapController() {
        return window.Na__ProfileTools__SwapController || null;
    }

    function Na__Ui__ReadSwapState() {
        var swap = Na__Ui__SwapController();
        return swap ? swap.Na__Swap__GetState() : null;
    }

    function Na__Ui__IsTraceBound() {
        var swap = Na__Ui__SwapController();
        return !!(swap && swap.Na__Swap__IsBound());
    }

    // Every placement control funnels through here. Nothing rebuilds on its own
    // — a rebuild is a full follow-me sweep plus an undo entry, so the user
    // presses Regenerate Trace when the settings are where they want them.
    function Na__Ui__MarkTraceDirty() {
        var swap = Na__Ui__SwapController();
        if (swap && swap.Na__Swap__IsBound()) swap.Na__Swap__MarkDirty();
    }

    // Adopts the placement Ruby just stamped on the trace, so the panel shows
    // what the assembly actually carries rather than whatever was last typed
    // into this tab for some other purpose.
    function Na__Ui__AdoptBoundPlacement(placement) {
        if (!placement) return;
        Na__UiState.rotationStep = Number(placement.rotationStep || 0) % 4;
        Na__UiState.originOffset = placement.originOffset || null;
        Na__UiState.isInsertPointPickActive = false;

        if (placement.toggleStates && typeof placement.toggleStates === 'object') {
            Object.keys(Na__UiState.toggleDefinitions || {}).forEach(function (toggleKey) {
                Na__UiState.toggleStates[toggleKey] = placement.toggleStates[toggleKey] === true;
            });
        }
    }

    // Single funnel for the three sources of a Reverse change: the button, the
    // TAB hotkey handled here, and TAB handled by the tool in the viewport.
    // shouldNotifyRuby is false for the last one, which is where the change came
    // from — pushing it back would bounce it straight to the tool again.
    function Na__Ui__SetReverseDirection(nextReverse, shouldNotifyRuby) {
        var resolvedReverse = nextReverse === true;
        if (resolvedReverse === Na__UiState.reverseDirection) return;

        Na__UiState.reverseDirection = resolvedReverse;
        Na__Ui__Render();
        Na__Ui__RenderProfilePreview();

        if (shouldNotifyRuby && window.Na__ProfilePathTracer__Bridge__SetReverseDirection) {
            window.Na__ProfilePathTracer__Bridge__SetReverseDirection(resolvedReverse);
        }
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
            Na__Ui__ClearInsertPointState();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Profile selected: ' + (profileKey || '[none]'));
        },
        Na__Events__OnPathModeChange: function(pathMode) {
            Na__UiState.pathMode = pathMode;
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Path mode: ' + (pathMode === 'interactive' ? 'Interactive path picking' : 'Use current selection'));
        },
        Na__Events__OnToggleInsertPointPick: function() {
            Na__UiState.isInsertPointPickActive = !Na__UiState.isInsertPointPickActive;
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus(Na__UiState.isInsertPointPickActive ?
                'Click a profile vertex in the preview to set the insertion point.' :
                'Insert point picking cancelled.');
        },
        Na__Events__OnPickInsertPointVertex: function(vertexIndex) {
            var sourcePoint = Na__UiState.previewSourcePoints[vertexIndex];
            if (!sourcePoint) {
                Na__Ui__SetStatus('That vertex could not be resolved — try another.');
                return;
            }

            Na__UiState.originOffset = { y: Number(sourcePoint[0]), z: Number(sourcePoint[1]) };
            Na__UiState.isInsertPointPickActive = false;
            Na__Ui__MarkTraceDirty();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Insert point moved to Y ' + Math.round(sourcePoint[0]) + 'mm, Z ' + Math.round(sourcePoint[1]) + 'mm.' +
                (Na__Ui__IsTraceBound() ? ' Click Regenerate Trace to apply it.' : ''));
        },
        Na__Events__OnResetInsertPoint: function() {
            Na__Ui__ClearInsertPointState();
            Na__Ui__MarkTraceDirty();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Insert point reset to the profile origin.');
        },
        Na__Events__OnRotateToStep: function(step) {
            Na__UiState.rotationStep = Math.max(0, Math.min(3, Number(step) || 0));
            Na__Ui__MarkTraceDirty();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Rotation set to ' + (Na__UiState.rotationStep * 90) + ' deg');
        },
        Na__Events__OnToggleChange: function(toggleKey, isEnabled) {
            if (!toggleKey) return;
            Na__UiState.toggleStates[toggleKey] = isEnabled;
            Na__Ui__MarkTraceDirty();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Toggle: ' + toggleKey + ' = ' + (isEnabled ? 'ON' : 'OFF'));
        },
        Na__Events__OnReverseDirectionToggle: function() {
            Na__Ui__SetReverseDirection(!Na__UiState.reverseDirection, true);
            Na__Ui__SetStatus('Reverse direction: ' + (Na__UiState.reverseDirection ? 'ON' : 'OFF'));
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
        Na__Events__OnAdvancedConfigToggle: function(isOpen) {
            Na__UiState.isAdvancedConfigOpen = isOpen === true;
        },
        Na__Events__OnSwapProfile: function() {
            var swap = Na__Ui__SwapController();
            if (!swap) {
                Na__Ui__SetStatus('Profile swap controller is not loaded.');
                return;
            }
            swap.Na__Swap__RequestBind();
        },
        Na__Events__OnRegenerateTrace: function() {
            var swap = Na__Ui__SwapController();
            if (!swap || !swap.Na__Swap__IsBound()) {
                Na__Ui__SetStatus('No Profile Trace is bound — use Swap Profile with a trace selected in the model.');
                return;
            }
            swap.Na__Swap__RegenerateBound({
                rotationStep: Na__UiState.rotationStep,
                toggleStates: Na__UiState.toggleStates,
                originOffset: Na__UiState.originOffset
            });
        },
        Na__Events__OnUnbindTrace: function() {
            var swap = Na__Ui__SwapController();
            if (swap) swap.Na__Swap__Unbind();
        },
        Na__Events__OnCancelSwapArm: function() {
            var swap = Na__Ui__SwapController();
            if (swap) swap.Na__Swap__CancelArm();
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

        Na__UiState.swap = Na__Ui__ReadSwapState();
        controlsRoot.innerHTML = window.Na__ProfilePathTracer__Ui__Controls.Na__Ui__RenderControls(Na__UiState);
        window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachEvents(Na__UiEventHandlers);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Store Event Handlers (keep Apply tab in sync with Gallery selection)
    // -------------------------------------------------------------------------

    function Na__Apply__OnStoreSelectedChanged(payload) {
        var isDifferentProfile = payload && payload.key && payload.key !== Na__UiState.profileKey;

        if (payload && payload.key) {
            Na__UiState.profileKey = payload.key;
            if (payload.record) {
                Na__UiState.profiles[payload.key] = payload.record;
            }
        }

        if (isDifferentProfile) {
            Na__Ui__ClearInsertPointState();
            Na__Ui__Render();
        }

        Na__Ui__UpdateActiveProfileIndicator();
        Na__Ui__RenderProfilePreview();
    }

    function Na__Apply__OnStoreMetaUpdated(payload) {
        if (payload && payload.key && payload.record) {
            Na__UiState.profiles[payload.key] = payload.record;
        }
        Na__Ui__UpdateActiveProfileIndicator();
        Na__Ui__RenderProfilePreview();
    }

    // A swap has just landed (or been armed / cancelled / unbound). Adopt the
    // placement Ruby stamped on the trace so the controls describe the assembly
    // that is now standing in the model, not the last thing typed here.
    function Na__Apply__OnSwapStateChanged(payload) {
        if (payload && payload.isBound === true && payload.isDirty !== true && !payload.isBusy) {
            Na__Ui__AdoptBoundPlacement(payload.placement);
        }
        Na__Ui__Render();
        Na__Ui__RenderProfilePreview();
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Lifecycle (mount / unmount contract)
    // -------------------------------------------------------------------------

    let na_is_subscribed = false;

    function na_mount() {
        var appCtx = window.Na_AppContext;
        if (appCtx && !na_is_subscribed) {
            na_is_subscribed = true;
            appCtx.na_subscribe('na_selected_changed',     Na__Apply__OnStoreSelectedChanged);
            appCtx.na_subscribe('na_profile_meta_updated', Na__Apply__OnStoreMetaUpdated);
            appCtx.na_subscribe('na_swap_state_changed',   Na__Apply__OnSwapStateChanged);
        }
        Na__Ui__SyncProfileKeyFromStore();

        // The swap that routed here dispatched before this tab had ever
        // mounted, so its placement event was never heard. Adopt it now or the
        // rotation pills and insert point would describe the last thing typed
        // in this tab rather than the trace standing in the model.
        var swapState = Na__Ui__ReadSwapState();
        if (swapState && swapState.isBound === true && swapState.isDirty !== true) {
            Na__Ui__AdoptBoundPlacement(swapState.placement);
        }

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
            Na__Ui__ClearInsertPointState();

            if (window.Na__ProfileTools__ProfileStore) {
                window.Na__ProfileTools__ProfileStore.Na__Store__SetProfiles(profileMap, Na__UiState.profileKey);
            }
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

    // TAB was pressed in the viewport — repaint the button to match the preview.
    function Na__ProfilePathTracer__ReceiveReverseDirectionState(payload) {
        if (!payload || typeof payload !== 'object') return;

        Na__Ui__SetReverseDirection(payload.reverseDirection === true, false);
        Na__Ui__SetStatus('Reverse direction: ' + (Na__UiState.reverseDirection ? 'ON' : 'OFF') + ' — flipped with TAB.');
    }

    // Sent when the interactive tool activates and again when it deactivates.
    function Na__ProfilePathTracer__ReceiveInteractiveToolState(payload) {
        if (!payload || typeof payload !== 'object') return;

        Na__UiState.isInteractiveToolActive = payload.isInteractiveToolActive === true;
        Na__Ui__SetReverseDirection(payload.reverseDirection === true, false);
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
    window.Na__ProfilePathTracer__ReceiveReverseDirectionState = Na__ProfilePathTracer__ReceiveReverseDirectionState;
    window.Na__ProfilePathTracer__ReceiveInteractiveToolState = Na__ProfilePathTracer__ReceiveInteractiveToolState;
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

    // The dialog steals focus the moment its Reverse button is clicked, so TAB
    // has to work here too — otherwise the hotkey would die on the first click.
    // Only armed while a trace is live, and never over a text field.
    function Na__Ui__IsTextEntryTarget(target) {
        if (!target || !target.tagName) return false;
        var tagName = target.tagName.toUpperCase();
        if (tagName === 'INPUT' || tagName === 'TEXTAREA' || tagName === 'SELECT') return true;
        return target.isContentEditable === true;
    }

    function Na__Ui__AttachReverseHotkey() {
        document.addEventListener('keydown', function(keyEvent) {
            if (keyEvent.key !== 'Tab') return;
            if (keyEvent.shiftKey || keyEvent.ctrlKey || keyEvent.altKey || keyEvent.metaKey) return;
            if (!Na__UiState.isInteractiveToolActive) return;
            if (Na__Ui__IsTextEntryTarget(keyEvent.target)) return;

            keyEvent.preventDefault();
            Na__UiEventHandlers.Na__Events__OnReverseDirectionToggle();
        });
    }

    document.addEventListener('DOMContentLoaded', function() {
        if (window.Na__ProfilePathTracer__Ui__Events && window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachHeaderEvents) {
            window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachHeaderEvents(Na__UiEventHandlers);
        }
        Na__Ui__AttachReverseHotkey();
    });

    // endregion ----------------------------------------------------------------
})();
