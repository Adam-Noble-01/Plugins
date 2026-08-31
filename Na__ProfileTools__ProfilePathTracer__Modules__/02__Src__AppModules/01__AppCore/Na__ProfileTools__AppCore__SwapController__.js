// =============================================================================
// NA PROFILE TOOLS - APP CORE - SWAP CONTROLLER
// =============================================================================
//
// FILE       : Na__ProfileTools__AppCore__SwapController__.js
// NAMESPACE  : window.Na__ProfileTools__SwapController
// PURPOSE    : Owns the "hot swap the profile on a placed trace" journey, which
//              spans two tabs and so belongs to neither.
//
// THE JOURNEY
//   1  BIND   - Swap Profile (Gallery toolbar, Apply Profile actions, or the
//               model right-click menu) asks Ruby which Profile Trace
//               assemblies the current model selection touches.
//   2  ARMED  - the Gallery is routed to and shows a pick banner. A card click
//               now means "swap to this" instead of "select this".
//   3  BOUND  - the swap runs, the trace rebuilds in the model, and the Apply
//               Profile tab is routed to with the trace still bound. Its
//               insert-point picker, rotation pills and mirror toggles now edit
//               THAT trace; Regenerate Trace applies them.
//
//   Bound state survives step 3 on purpose — the insert point is the setting
//   users most often want to correct straight after seeing the new profile in
//   place, and re-picking the trace in the model to do it would be busywork.
//
// EVENTS (dispatched via Na_AppContext.na_dispatch)
//   na_swap_state_changed - payload: the full state object below
//
// STATE IS ADDRESSED BY TRACE ID, NOT BY OBJECT
//   Ruby re-resolves every NPTnnnn id from the model at swap time, so the user
//   is free to click around, change the selection, or undo between arming and
//   picking without the binding going stale.
//
// LOAD ORDER : after BridgeBase + ProfileStore, before the tab modules.
//
// =============================================================================

(function () {
    'use strict';

    var Na__ProfileTools__SwapController = {};

    // -------------------------------------------------------------------------
    // REGION | Internal State
    // -------------------------------------------------------------------------

    function na_empty_state() {
        return {
            isArmed:            false,   // gallery is waiting for a replacement pick
            isBound:            false,   // one or more traces are bound to the panel
            isBusy:             false,   // a bind / swap round trip is in flight
            isDirty:            false,   // placement edited since the last rebuild
            traceIds:           [],
            traceCount:         0,
            primaryTraceId:     '',
            primaryProfileKey:  '',
            primaryProfileName: '',
            primaryGroupName:   '',
            placement: {
                rotationStep:     0,
                toggleStates:     {},
                originOffset:     null,
                reverseDirection: false
            }
        };
    }

    var na_state = na_empty_state();

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Bus + Bridge Helpers
    // -------------------------------------------------------------------------

    function na_dispatch() {
        if (window.Na_AppContext && typeof window.Na_AppContext.na_dispatch === 'function') {
            window.Na_AppContext.na_dispatch('na_swap_state_changed', Na__ProfileTools__SwapController.Na__Swap__GetState());
        }
    }

    function na_status(message) {
        if (window.Na__ProfileTools__BridgeBase) {
            window.Na__ProfileTools__BridgeBase.Na__BridgeBase__SetStatus(message);
            return;
        }
        var statusEl = document.getElementById('na-status-message');
        if (statusEl) statusEl.textContent = message || '';
    }

    function na_call(callbackName, payload) {
        if (!window.Na__ProfileTools__BridgeBase) {
            na_status('SketchUp bridge is not available — profile swap needs the plugin dialog.');
            return false;
        }
        return window.Na__ProfileTools__BridgeBase.Na__BridgeBase__CallSafe(callbackName, payload);
    }

    function na_activate_tab(tabId) {
        if (window.Na_TabRouter && typeof window.Na_TabRouter.na_activateTab === 'function') {
            window.Na_TabRouter.na_activateTab(tabId);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | State Adoption
    // -------------------------------------------------------------------------

    function na_adopt_bind_payload(payload) {
        if (!payload || payload.isBound !== true) {
            na_state = na_empty_state();
            return false;
        }

        var placement = payload.placement || {};
        na_state.isBound            = true;
        na_state.traceIds           = Array.isArray(payload.traceIds) ? payload.traceIds.slice() : [];
        na_state.traceCount         = payload.traceCount || na_state.traceIds.length;
        na_state.primaryTraceId     = payload.primaryTraceId || '';
        na_state.primaryProfileKey  = payload.primaryProfileKey || '';
        na_state.primaryProfileName = payload.primaryProfileName || '';
        na_state.primaryGroupName   = payload.primaryGroupName || '';
        na_state.placement = {
            rotationStep:     Number(placement.rotationStep || 0) % 4,
            toggleStates:     (placement.toggleStates && typeof placement.toggleStates === 'object') ? placement.toggleStates : {},
            originOffset:     placement.originOffset || null,
            reverseDirection: placement.reverseDirection === true
        };
        return true;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public - State Accessors
    // -------------------------------------------------------------------------

    // Returned as a copy so a tab renderer cannot mutate the controller's own
    // state by editing what it was handed.
    Na__ProfileTools__SwapController.Na__Swap__GetState = function () {
        return {
            isArmed:            na_state.isArmed,
            isBound:            na_state.isBound,
            isBusy:             na_state.isBusy,
            isDirty:            na_state.isDirty,
            traceIds:           na_state.traceIds.slice(),
            traceCount:         na_state.traceCount,
            primaryTraceId:     na_state.primaryTraceId,
            primaryProfileKey:  na_state.primaryProfileKey,
            primaryProfileName: na_state.primaryProfileName,
            primaryGroupName:   na_state.primaryGroupName,
            placement: {
                rotationStep:     na_state.placement.rotationStep,
                toggleStates:     na_state.placement.toggleStates,
                originOffset:     na_state.placement.originOffset,
                reverseDirection: na_state.placement.reverseDirection
            }
        };
    };

    Na__ProfileTools__SwapController.Na__Swap__IsArmed = function () { return na_state.isArmed === true; };
    Na__ProfileTools__SwapController.Na__Swap__IsBound = function () { return na_state.isBound === true; };
    Na__ProfileTools__SwapController.Na__Swap__IsBusy  = function () { return na_state.isBusy  === true; };

    Na__ProfileTools__SwapController.Na__Swap__TraceLabel = function () {
        if (!na_state.isBound) return '';
        var name  = na_state.primaryProfileName || na_state.primaryProfileKey || '';
        var label = na_state.primaryTraceId + (name ? ' — ' + name : '');
        if (na_state.traceCount > 1) {
            label += ' (+' + (na_state.traceCount - 1) + ' more)';
        }
        return label;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public - Step 1: Bind From Model Selection
    // -------------------------------------------------------------------------

    Na__ProfileTools__SwapController.Na__Swap__RequestBind = function () {
        if (na_state.isBusy) return;
        na_state.isBusy = true;
        na_dispatch();
        na_status('Reading the model selection for a Profile Trace to swap...');
        if (!na_call('na_profilepathtracer_bind_swap_target')) {
            na_state.isBusy = false;
            na_dispatch();
        }
    };

    // Ruby -> here. A failed bind leaves the previous binding alone: losing the
    // trace you already had because you clicked Swap with nothing selected
    // would be a worse outcome than the message telling you to select one.
    Na__ProfileTools__SwapController.Na__Swap__OnTargetReceived = function (payload) {
        na_state.isBusy = false;

        if (!payload || payload.isBound !== true) {
            na_status((payload && payload.statusMessage) || 'No Profile Trace assembly is selected in the model.');
            na_dispatch();
            return;
        }

        na_adopt_bind_payload(payload);
        na_state.isArmed = true;
        na_state.isDirty = false;

        // Point the whole app at the profile the trace currently carries, so
        // the Gallery opens with it highlighted and the user can see what they
        // are replacing. Dispatched BEFORE the swap event: the Apply tab drops
        // its insert point on a profile change, and the swap event is what puts
        // the trace's own stored datum back.
        na_select_current_profile();

        na_dispatch();
        na_activate_tab('gallery');
        na_status(payload.statusMessage || 'Pick a replacement profile in the Gallery.');
    };

    function na_select_current_profile() {
        var store = window.Na__ProfileTools__ProfileStore;
        if (!store || !na_state.primaryProfileKey) return;
        if (!store.Na__Store__GetProfile(na_state.primaryProfileKey)) return;
        store.Na__Store__SetSelected(na_state.primaryProfileKey, { navigate: false });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public - Step 2: Apply A Picked Profile
    // -------------------------------------------------------------------------

    Na__ProfileTools__SwapController.Na__Swap__ApplyProfile = function (profileKey) {
        if (!na_state.isBound || !profileKey) return false;
        if (na_state.isBusy) return false;

        na_state.isBusy = true;
        na_dispatch();
        na_status('Swapping ' + na_state.traceCount + ' trace(s) to ' + profileKey + '...');

        // No originOffset sent: the stored datum was picked in the OLD profile's
        // millimetre space, so Ruby resets it to the new profile's own origin.
        var sent = na_call('na_profilepathtracer_apply_profile_swap', {
            traceIds:   na_state.traceIds,
            profileKey: profileKey
        });

        if (!sent) {
            na_state.isBusy = false;
            na_dispatch();
        }
        return sent;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public - Step 3: Regenerate The Bound Trace
    // -------------------------------------------------------------------------

    // Same Ruby entry point with a blank profileKey — "keep the profile, apply
    // these placement settings". This is what the Regenerate Trace button sends
    // after the insert point, rotation or mirrors have been changed.
    Na__ProfileTools__SwapController.Na__Swap__RegenerateBound = function (placement) {
        if (!na_state.isBound) return false;
        if (na_state.isBusy) return false;

        var resolved = placement || {};
        na_state.isBusy = true;
        na_dispatch();
        na_status('Regenerating ' + na_state.traceCount + ' bound trace(s)...');

        var sent = na_call('na_profilepathtracer_apply_profile_swap', {
            traceIds:     na_state.traceIds,
            profileKey:   '',
            rotationStep: Number(resolved.rotationStep || 0) % 4,
            toggleStates: resolved.toggleStates || {},
            originOffset: resolved.originOffset || null
        });

        if (!sent) {
            na_state.isBusy = false;
            na_dispatch();
        }
        return sent;
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public - Result Handling
    // -------------------------------------------------------------------------

    Na__ProfileTools__SwapController.Na__Swap__OnResultReceived = function (result) {
        na_state.isBusy  = false;
        na_state.isArmed = false;

        if (result && result.bind) {
            na_adopt_bind_payload(result.bind);
        }
        if (result && result.isSwapped === true) {
            na_state.isDirty = false;
        }

        na_dispatch();
        na_activate_tab('apply-profile');
        na_status((result && result.statusMessage) || 'Profile swap finished.');
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public - Dirty Marking + Teardown
    // -------------------------------------------------------------------------

    // Placement edits never rebuild on their own: each rebuild is a full
    // follow-me sweep and its own undo step, so firing on every vertex click
    // would be both slow and destructive to the undo stack.
    Na__ProfileTools__SwapController.Na__Swap__MarkDirty = function () {
        if (!na_state.isBound || na_state.isDirty) return;
        na_state.isDirty = true;
        na_dispatch();
    };

    Na__ProfileTools__SwapController.Na__Swap__CancelArm = function () {
        if (!na_state.isArmed) return;
        na_state.isArmed = false;
        na_dispatch();
        na_status('Profile swap cancelled — the trace is still bound.');
    };

    Na__ProfileTools__SwapController.Na__Swap__Unbind = function () {
        na_state = na_empty_state();
        na_dispatch();
        na_status('Trace unbound. The Apply Profile tab is back to generating new traces.');
    };

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__SwapController = Na__ProfileTools__SwapController;

    window.Na__ProfilePathTracer__ReceiveSwapTarget = Na__ProfileTools__SwapController.Na__Swap__OnTargetReceived;
    window.Na__ProfilePathTracer__ReceiveSwapResult = Na__ProfileTools__SwapController.Na__Swap__OnResultReceived;

    // endregion ----------------------------------------------------------------
})();
