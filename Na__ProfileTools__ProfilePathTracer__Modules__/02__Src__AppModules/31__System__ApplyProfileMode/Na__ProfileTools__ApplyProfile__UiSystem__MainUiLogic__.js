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
        // Mirrors the running preview tool — the Interactive trace or the
        // Selection preview. Only true while one is live, which is the only time
        // TAB is ours to take from focus traversal.
        isInteractiveToolActive: false,
        // 'interactive' | 'selectionPreview' while a tool is live, else ''.
        // A live Selection preview swaps Generate for Commit / Cancel.
        liveToolKind: '',
        livePathSummary: '',
        // Signed millimetres the sweep runs past the Start / End of an open
        // path (negative trims). Start is the first click in Interactive mode
        // and the end tagged "Start" in the Selection preview.
        startOffsetMm: 0,
        endOffsetMm: 0,
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
        // Library mode shows a list: follow the store's selection there, and
        // redraw only if that profile has no option yet (added since drawn).
        var selectEl = document.getElementById('naSelectActiveProfile');
        if (selectEl) {
            var selectStore = window.Na__ProfileTools__ProfileStore;
            var selectedKey = selectStore ? selectStore.Na__Store__GetSelectedKey() : '';
            if (!selectedKey || selectEl.value === selectedKey) return;
            var hasOption = Array.prototype.some.call(selectEl.options, function(option) {
                return option.value === selectedKey;
            });
            if (hasOption) {
                selectEl.value = selectedKey;
            } else {
                Na__Ui__Render();
            }
            return;
        }

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
            toggleStates: Na__UiState.toggleStates,
            startOffsetMm: Na__UiState.startOffsetMm,
            endOffsetMm: Na__UiState.endOffsetMm
        };
    }

    // While a preview tool is running, every placement edit is sent across
    // whole, so the viewport redraws with it — a profile picked mid-preview,
    // a rotation, a mirror, the insert point or an offset.
    function Na__Ui__PushLivePlacement() {
        if (!Na__UiState.isInteractiveToolActive) return;
        if (typeof window.Na__ProfilePathTracer__Bridge__UpdateLivePlacement !== 'function') return;
        window.Na__ProfilePathTracer__Bridge__UpdateLivePlacement(Na__Ui__BuildGeneratePayload());
    }

    function Na__Ui__IsSelectionPreviewLive() {
        return Na__UiState.isInteractiveToolActive === true && Na__UiState.liveToolKind === 'selectionPreview';
    }

    // A datum picked on one profile means nothing on another, so switching the
    // active profile drops the offset instead of silently re-datuming the new one.
    function Na__Ui__ClearInsertPointState() {
        Na__UiState.originOffset = null;
        Na__UiState.isInsertPointPickActive = false;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Path Offsets (parse + apply)
    // -------------------------------------------------------------------------

    var NA_PATH_OFFSET_LIMIT_MM = 50000;
    var NA_LENGTH_UNIT_TO_MM = { '': 1, 'mm': 1, 'cm': 10, 'm': 1000, 'in': 25.4, '"': 25.4, 'ft': 304.8, "'": 304.8 };

    // Read the way an architect types it: a bare number is millimetres, a unit
    // suffix is honoured (0.15m, 15cm, 6in) and commas are thousands separators
    // (1,500 is 1500). Anything else is refused with the fix named — never
    // guessed at, never clamped. Returns { isValid, valueMm, reason }.
    function Na__Ui__ParseOffsetMm(text) {
        var raw = String(text === null || text === undefined ? '' : text).trim();
        if (raw === '') return { isValid: true, valueMm: 0, reason: '' };

        var compact = raw.replace(/,/g, '').replace(/\s+/g, '').toLowerCase();
        var match = compact.match(/^([+-]?(?:\d+\.?\d*|\.\d+))(mm|cm|m|in|"|ft|')?$/);
        if (!match) {
            return { isValid: false, valueMm: 0,
                     reason: '"' + raw + '" is not a length. Type millimetres, e.g. 150 or -50 (0.15m and 6in work too).' };
        }

        var valueMm = parseFloat(match[1]) * NA_LENGTH_UNIT_TO_MM[match[2] || ''];
        if (!isFinite(valueMm)) {
            return { isValid: false, valueMm: 0, reason: '"' + raw + '" is not a length.' };
        }
        if (Math.abs(valueMm) > NA_PATH_OFFSET_LIMIT_MM) {
            return { isValid: false, valueMm: 0,
                     reason: Math.round(valueMm) + 'mm is past the ' + NA_PATH_OFFSET_LIMIT_MM + 'mm limit. A bare number is millimetres, e.g. 150.' };
        }
        return { isValid: true, valueMm: Math.round(valueMm * 10) / 10, reason: '' };
    }

    function Na__Ui__DescribeOffset(valueMm) {
        if (valueMm > 0) return '+' + valueMm + 'mm overshoot';
        if (valueMm < 0) return valueMm + 'mm trim';
        return 'none';
    }

    // Applies one box synchronously — state and the push to a running preview —
    // so a Commit clicked straight out of the box builds with the new value.
    // Returns the status line; the caller redraws the panel.
    function Na__Ui__ApplyPathOffset(endKey, text) {
        var stateKey = endKey === 'end' ? 'endOffsetMm' : 'startOffsetMm';
        var label    = endKey === 'end' ? 'End' : 'Start';
        var parsed   = Na__Ui__ParseOffsetMm(text);
        if (!parsed.isValid) {
            return { isChanged: false, message: label + ' offset not changed: ' + parsed.reason };
        }

        var isChanged = parsed.valueMm !== Na__UiState[stateKey];
        Na__UiState[stateKey] = parsed.valueMm;
        if (isChanged) Na__Ui__PushLivePlacement();

        var suffix = '';
        if (isChanged && Na__Ui__IsTraceBound()) {
            suffix = ' Click Regenerate Trace to apply it.';
        } else if (isChanged && Na__UiState.isInteractiveToolActive) {
            suffix = ' Preview updated.';
        }
        return {
            isChanged: isChanged,
            message: label + ' offset: ' + Na__Ui__DescribeOffset(parsed.valueMm) + '.' + suffix
        };
    }

    // A box can still hold text that failed to parse (its change was refused).
    // Generate, Commit and Regenerate check first, so nothing is built with a
    // value the user can see is not the one being used.
    function Na__Ui__PendingOffsetProblem() {
        var inputs = document.querySelectorAll('.na-offset-field__input[data-na-offset-end]');
        for (var i = 0; i < inputs.length; i++) {
            var parsed = Na__Ui__ParseOffsetMm(inputs[i].value);
            if (!parsed.isValid) {
                var label = inputs[i].getAttribute('data-na-offset-end') === 'end' ? 'End' : 'Start';
                return label + ' offset: ' + parsed.reason;
            }
        }
        return '';
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
        Na__UiState.startOffsetMm = Number(placement.startOffset) || 0;
        Na__UiState.endOffsetMm = Number(placement.endOffset) || 0;

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
            Na__Ui__PushLivePlacement();
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
            Na__Ui__PushLivePlacement();
            Na__Ui__SetStatus('Profile selected: ' + (profileKey || '[none]'));
        },
        // The Active Profile list. Routed through the store, like a Gallery
        // pick, so every tab agrees — the store change is what redraws this
        // panel and pushes the new profile to a running preview.
        Na__Events__OnActiveProfileSelect: function(profileKey) {
            var store = window.Na__ProfileTools__ProfileStore;
            if (store && store.Na__Store__GetProfile(profileKey)) {
                store.Na__Store__SetSelected(profileKey, { navigate: false });
                var record = store.Na__Store__GetSelectedRecord();
                Na__Ui__SetStatus('Profile: ' + (store.Na__Store__ProfileLabel(record) || profileKey) +
                    (Na__UiState.isInteractiveToolActive ? ' — preview updated.' : '.'));
                return;
            }
            Na__UiEventHandlers.Na__Events__OnProfileChange(profileKey);
        },
        Na__Events__OnPathModeChange: function(pathMode) {
            var wasPreviewing = Na__Ui__IsSelectionPreviewLive();
            Na__UiState.pathMode = pathMode;
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Path mode: ' + (pathMode === 'interactive' ? 'Interactive path picking' : 'Use current selection'));

            // The preview belongs to Selection mode; leaving the mode leaves it.
            if (wasPreviewing && pathMode !== 'selection' && window.Na__ProfilePathTracer__Bridge__CancelLiveTool) {
                window.Na__ProfilePathTracer__Bridge__CancelLiveTool();
            }
        },
        // Applied at once so a Commit clicked straight out of the box builds
        // with it; the redraw waits a tick, because `change` fires while focus
        // is still moving to the next control (TAB from Start into End) and
        // redrawing now would drop it. Na__Ui__Render puts focus back after.
        Na__Events__OnPathOffsetChange: function(endKey, text) {
            var outcome = Na__Ui__ApplyPathOffset(endKey, text);
            window.setTimeout(function() {
                if (outcome.isChanged) Na__Ui__MarkTraceDirty();
                Na__Ui__Render();
                Na__Ui__RenderProfilePreview();
                Na__Ui__SetStatus(outcome.message);
            }, 0);
        },
        Na__Events__OnSwapPathOffsets: function() {
            var startOffsetMm = Na__UiState.startOffsetMm;
            Na__UiState.startOffsetMm = Na__UiState.endOffsetMm;
            Na__UiState.endOffsetMm = startOffsetMm;
            Na__Ui__PushLivePlacement();
            Na__Ui__MarkTraceDirty();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__SetStatus('Offsets swapped: Start ' + Na__Ui__DescribeOffset(Na__UiState.startOffsetMm) +
                ', End ' + Na__Ui__DescribeOffset(Na__UiState.endOffsetMm) + '.' +
                (Na__Ui__IsTraceBound() ? ' Click Regenerate Trace to apply them.' : ''));
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
            Na__Ui__PushLivePlacement();
            Na__Ui__SetStatus('Insert point moved to Y ' + Math.round(sourcePoint[0]) + 'mm, Z ' + Math.round(sourcePoint[1]) + 'mm.' +
                (Na__Ui__IsTraceBound() ? ' Click Regenerate Trace to apply it.' : ''));
        },
        Na__Events__OnResetInsertPoint: function() {
            Na__Ui__ClearInsertPointState();
            Na__Ui__MarkTraceDirty();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__PushLivePlacement();
            Na__Ui__SetStatus('Insert point reset to the profile origin.');
        },
        Na__Events__OnRotateToStep: function(step) {
            Na__UiState.rotationStep = Math.max(0, Math.min(3, Number(step) || 0));
            Na__Ui__MarkTraceDirty();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__PushLivePlacement();
            Na__Ui__SetStatus('Rotation set to ' + (Na__UiState.rotationStep * 90) + ' deg');
        },
        Na__Events__OnToggleChange: function(toggleKey, isEnabled) {
            if (!toggleKey) return;
            Na__UiState.toggleStates[toggleKey] = isEnabled;
            Na__Ui__MarkTraceDirty();
            Na__Ui__Render();
            Na__Ui__RenderProfilePreview();
            Na__Ui__PushLivePlacement();
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
            var offsetProblem = Na__Ui__PendingOffsetProblem();
            if (offsetProblem) {
                Na__Ui__SetStatus('Fix the offset first — ' + offsetProblem);
                return;
            }
            Na__UiState.lastGeneratePayload = Na__Ui__BuildGeneratePayload();
            if (window.Na__ProfilePathTracer__Bridge__Generate) {
                window.Na__ProfilePathTracer__Bridge__Generate(Na__UiState.lastGeneratePayload);
            }
        },
        Na__Events__OnCommitPreview: function() {
            if (!Na__Ui__IsSelectionPreviewLive()) {
                Na__Ui__SetStatus('No selection preview is running — select the path edges and click Generate Profile first.');
                return;
            }
            var offsetProblem = Na__Ui__PendingOffsetProblem();
            if (offsetProblem) {
                Na__Ui__SetStatus('Fix the offset first — ' + offsetProblem);
                return;
            }
            if (window.Na__ProfilePathTracer__Bridge__CommitLiveTool) {
                window.Na__ProfilePathTracer__Bridge__CommitLiveTool();
            }
        },
        Na__Events__OnCancelPreview: function() {
            if (window.Na__ProfilePathTracer__Bridge__CancelLiveTool) {
                window.Na__ProfilePathTracer__Bridge__CancelLiveTool();
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
            var offsetProblem = Na__Ui__PendingOffsetProblem();
            if (offsetProblem) {
                Na__Ui__SetStatus('Fix the offset first — ' + offsetProblem);
                return;
            }
            swap.Na__Swap__RegenerateBound({
                rotationStep: Na__UiState.rotationStep,
                toggleStates: Na__UiState.toggleStates,
                originOffset: Na__UiState.originOffset,
                startOffset:  Na__UiState.startOffsetMm,
                endOffset:    Na__UiState.endOffsetMm
            });
        },
        // Straight through to Ruby. There is nothing to validate here: the
        // navigator works from the model selection, which this side cannot see,
        // and it already returns a specific message for every way it can fail
        // ("select a trace first", "no Helpers sub-group", "locked context").
        // A guess made here would only be able to say something vaguer.
        Na__Events__OnOpenPathEditor: function() {
            if (window.Na__ProfilePathTracer__Bridge__OpenPathEditor) {
                window.Na__ProfilePathTracer__Bridge__OpenPathEditor();
                return;
            }
            Na__Ui__SetStatus('Open path bridge is not available.');
        },
        // Edit Profile: the Draw Profile tab reads the model selection and,
        // for a trace, opens its profile bound to it.
        Na__Events__OnOpenDrawEditor: function() {
            var drawTab = window.Na__ProfileTools__DrawProfile__Tab;
            if (drawTab && typeof drawTab.na_open_from_model === 'function') {
                drawTab.na_open_from_model();
                return;
            }
            Na__Ui__SetStatus('The Draw Profile editor is not loaded. Reload the plugin, then reopen the dialog.');
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

        var focusSnapshot = Na__Ui__CaptureFieldFocus(controlsRoot);

        Na__UiState.swap = Na__Ui__ReadSwapState();
        controlsRoot.innerHTML = window.Na__ProfilePathTracer__Ui__Controls.Na__Ui__RenderControls(Na__UiState);
        window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachEvents(Na__UiEventHandlers);

        Na__Ui__RestoreFieldFocus(focusSnapshot);
    }

    // The panel is rebuilt wholesale, so a field the user is in — the End
    // Offset box they just tabbed into, or the profile list they are arrowing
    // through — would lose focus on every redraw. Form fields only: putting
    // focus back on a BUTTON would let Enter re-press it instead of reaching
    // the Commit hotkey.
    function Na__Ui__CaptureFieldFocus(root) {
        var active = document.activeElement;
        if (!active || !active.id || !root.contains(active)) return null;
        var tagName = (active.tagName || '').toUpperCase();
        if (tagName !== 'INPUT' && tagName !== 'SELECT' && tagName !== 'TEXTAREA') return null;

        var snapshot = { id: active.id, selectionStart: null, selectionEnd: null };
        try {
            if (typeof active.selectionStart === 'number') {
                snapshot.selectionStart = active.selectionStart;
                snapshot.selectionEnd = active.selectionEnd;
            }
        } catch (err) { /* field type without a caret */ }
        return snapshot;
    }

    function Na__Ui__RestoreFieldFocus(snapshot) {
        if (!snapshot) return;
        var field = document.getElementById(snapshot.id);
        if (!field || typeof field.focus !== 'function') return;
        field.focus();
        if (snapshot.selectionStart !== null && typeof field.setSelectionRange === 'function') {
            try { field.setSelectionRange(snapshot.selectionStart, snapshot.selectionEnd); }
            catch (err) { /* value shorter than the old caret — leave it where focus put it */ }
        }
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
            // A Gallery pick or the Active Profile list, mid-preview: the
            // running tool redraws with the new profile.
            Na__Ui__PushLivePlacement();
        }

        Na__Ui__UpdateActiveProfileIndicator();
        Na__Ui__RenderProfilePreview();
    }

    function Na__Apply__OnStoreMetaUpdated(payload) {
        if (payload && payload.key && payload.record) {
            Na__UiState.profiles[payload.key] = payload.record;
            Na__Apply__RelabelProfileOption(payload.key, payload.record);
        }
        Na__Ui__UpdateActiveProfileIndicator();
        Na__Ui__RenderProfilePreview();
    }

    // A rename in the Edit tab arrives once per keystroke, so the one option
    // is relabelled in place rather than the whole panel redrawn.
    function Na__Apply__RelabelProfileOption(profileKey, record) {
        var selectEl = document.getElementById('naSelectActiveProfile');
        var store    = window.Na__ProfileTools__ProfileStore;
        if (!selectEl || !store) return;
        Array.prototype.forEach.call(selectEl.options, function(option) {
            if (option.value === profileKey) {
                option.textContent = store.Na__Store__ProfileLabel(record) || profileKey;
            }
        });
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

    // Sent when a preview tool (Interactive or Selection) activates and again
    // when it deactivates. Always a full redraw: whether a Selection preview
    // is live decides between Generate and Commit / Cancel.
    function Na__ProfilePathTracer__ReceiveInteractiveToolState(payload) {
        if (!payload || typeof payload !== 'object') return;

        var isActive = payload.isInteractiveToolActive === true;
        Na__UiState.isInteractiveToolActive = isActive;
        Na__UiState.liveToolKind    = isActive ? (payload.toolKind || 'interactive') : '';
        Na__UiState.livePathSummary = isActive ? (payload.pathSummary || '') : '';
        Na__UiState.reverseDirection = payload.reverseDirection === true;
        Na__Ui__Render();
        Na__Ui__RenderProfilePreview();
    }

    // SHIFT+TAB rolled the profile in the viewport. Follow it here, or this
    // panel's next placement push would roll it straight back.
    function Na__ProfilePathTracer__ReceiveRotationState(payload) {
        if (!payload || typeof payload !== 'object') return;

        Na__UiState.rotationStep = Math.max(0, Math.min(3, Number(payload.rotationStep) || 0));
        Na__Ui__Render();
        Na__Ui__RenderProfilePreview();
        Na__Ui__SetStatus('Rotation ' + (Na__UiState.rotationStep * 90) + ' deg — rolled with SHIFT+TAB.');
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
    window.Na__ProfilePathTracer__ReceiveRotationState      = Na__ProfilePathTracer__ReceiveRotationState;
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

    // The dialog steals focus the moment one of its buttons is clicked, so the
    // viewport keys have to work here too — otherwise they would die on the
    // first click. Only armed while a preview tool is live, and never over a
    // text field.
    function Na__Ui__IsTextEntryTarget(target) {
        if (!target || !target.tagName) return false;
        var tagName = target.tagName.toUpperCase();
        if (tagName === 'INPUT' || tagName === 'TEXTAREA' || tagName === 'SELECT') return true;
        return target.isContentEditable === true;
    }

    // Enter / Esc keep their own meaning on anything that has one: a focused
    // button is pressed by Enter, a disclosure toggled.
    function Na__Ui__IsControlTarget(target) {
        if (Na__Ui__IsTextEntryTarget(target)) return true;
        if (!target || !target.tagName) return false;
        var tagName = target.tagName.toUpperCase();
        return tagName === 'BUTTON' || tagName === 'A' || tagName === 'SUMMARY';
    }

    //   TAB        reverse            (both preview tools, as in the viewport)
    //   SHIFT+TAB  rotate 90 deg      (both preview tools, as in the viewport)
    //   Enter      commit             (Selection preview)
    //   Esc        cancel             (Selection preview — an Interactive trace
    //                                  has waypoints to lose, so its Esc stays
    //                                  in the viewport)
    function Na__Ui__AttachLiveToolHotkeys() {
        document.addEventListener('keydown', function(keyEvent) {
            if (!Na__UiState.isInteractiveToolActive) return;
            if (keyEvent.ctrlKey || keyEvent.altKey || keyEvent.metaKey) return;

            if (keyEvent.key === 'Tab') {
                if (Na__Ui__IsTextEntryTarget(keyEvent.target)) return;
                keyEvent.preventDefault();
                if (keyEvent.shiftKey) {
                    Na__UiEventHandlers.Na__Events__OnRotateToStep((Na__UiState.rotationStep + 1) % 4);
                } else {
                    Na__UiEventHandlers.Na__Events__OnReverseDirectionToggle();
                }
                return;
            }

            if (!Na__Ui__IsSelectionPreviewLive() || keyEvent.shiftKey) return;
            if (Na__Ui__IsControlTarget(keyEvent.target)) return;

            if (keyEvent.key === 'Enter') {
                keyEvent.preventDefault();
                Na__UiEventHandlers.Na__Events__OnCommitPreview();
            } else if (keyEvent.key === 'Escape') {
                keyEvent.preventDefault();
                Na__UiEventHandlers.Na__Events__OnCancelPreview();
            }
        });
    }

    document.addEventListener('DOMContentLoaded', function() {
        if (window.Na__ProfilePathTracer__Ui__Events && window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachHeaderEvents) {
            window.Na__ProfilePathTracer__Ui__Events.Na__Ui__AttachHeaderEvents(Na__UiEventHandlers);
        }
        Na__Ui__AttachLiveToolHotkeys();
    });

    // endregion ----------------------------------------------------------------
})();
