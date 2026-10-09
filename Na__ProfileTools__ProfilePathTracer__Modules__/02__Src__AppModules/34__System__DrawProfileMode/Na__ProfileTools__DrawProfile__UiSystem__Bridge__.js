/* =============================================================================
   NA PROFILE TOOLS - DRAW PROFILE - UI SYSTEM - BRIDGE
   =============================================================================
   FILE       : Na__ProfileTools__DrawProfile__UiSystem__Bridge__.js
   NAMESPACE  : window.Na__DrawProfile__Bridge__ResolveSelection
                window.Na__DrawProfile__Bridge__Save
                window.Na__DrawProfile__Bridge__CountUsage
                window.Na__DrawProfile__Bridge__ApplyLocal
                window.Na__DrawProfile__Bridge__RevertLocal
                window.Na__DrawProfile__Bridge__RequestPalette
                window.Na__ProfilePathTracer__ReceiveDrawSelection
                window.Na__ProfilePathTracer__ReceiveDrawPalette
                window.Na__ProfilePathTracer__ReceiveDrawLocalResult
                window.Na__ProfilePathTracer__ReceiveDrawSaveResult
                window.Na__ProfilePathTracer__ReceiveDrawKeyUsage
   PURPOSE    : JS -> Ruby for the Draw Profile tab, and the receivers Ruby
                answers on (Na__ProfileTools__DrawProfile__DialogHandlers__.rb).

   DISPATCH CONTRACT (as the Edit Profile bridge)
                A send returns true only when it reached Ruby, so the tab can
                re-enable at once on false rather than wait for an answer that
                is not coming.
   ============================================================================= */

(function () {
    'use strict';

    function Na__DrawBridge__Call(name, payload) {
        if (!(window.sketchup && typeof window.sketchup[name] === 'function')) return false;
        try {
            if (payload === undefined) window.sketchup[name]();
            else window.sketchup[name](JSON.stringify(payload));
            return true;
        } catch (err) {
            console.error('[DrawProfile Bridge] ' + name + ' failed', err);
            return false;
        }
    }

    function Na__DrawBridge__NotifyTab(handlerName, payload) {
        var tab = window.Na__ProfileTools__DrawProfile__Tab;
        if (tab && typeof tab[handlerName] === 'function') tab[handlerName](payload);
    }

    // -------------------------------------------------------------------------
    // REGION | JS -> Ruby
    // -------------------------------------------------------------------------

    function Na__DrawProfile__Bridge__ResolveSelection() {
        return Na__DrawBridge__Call('na_profilepathtracer_draw_resolve_selection');
    }

    function Na__DrawProfile__Bridge__Save(params) {
        return Na__DrawBridge__Call('na_profilepathtracer_draw_save', params || {});
    }

    function Na__DrawProfile__Bridge__CountUsage(profileKey) {
        return Na__DrawBridge__Call('na_profilepathtracer_draw_count_usage', { profileKey : profileKey || '' });
    }

    // This trace only: the drawing goes onto the bound trace(s) as their own
    // local profile; the library is not touched (Update This Trace, Live).
    function Na__DrawProfile__Bridge__ApplyLocal(params) {
        return Na__DrawBridge__Call('na_profilepathtracer_draw_apply_local', params || {});
    }

    function Na__DrawProfile__Bridge__RevertLocal(params) {
        return Na__DrawBridge__Call('na_profilepathtracer_draw_revert_local', params || {});
    }

    // Edge Paint: the SSOT edge colours (refresh fetches them again first).
    function Na__DrawProfile__Bridge__RequestPalette(refresh) {
        return Na__DrawBridge__Call('na_profilepathtracer_draw_edge_palette', { refresh : !!refresh });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Ruby -> JS
    // -------------------------------------------------------------------------

    function Na__ProfilePathTracer__ReceiveDrawSelection(payload) {
        Na__DrawBridge__NotifyTab('na_receive_selection', payload || {});
    }

    // A saved profile goes into the shared store straight away, so the Gallery,
    // Apply and Edit tabs all see it; the selection is left where it is.
    function Na__ProfilePathTracer__ReceiveDrawSaveResult(result) {
        var outcome = result || {};
        if (outcome.isSaved && outcome.profileKey && outcome.profileRecord) {
            var store = window.Na__ProfileTools__ProfileStore;
            if (store) store.Na__Store__UpdateRecord(outcome.profileKey, outcome.profileRecord);
        }
        Na__DrawBridge__NotifyTab('na_receive_save_result', outcome);
    }

    function Na__ProfilePathTracer__ReceiveDrawKeyUsage(payload) {
        Na__DrawBridge__NotifyTab('na_receive_key_usage', payload || {});
    }

    function Na__ProfilePathTracer__ReceiveDrawLocalResult(result) {
        Na__DrawBridge__NotifyTab('na_receive_local_result', result || {});
    }

    function Na__ProfilePathTracer__ReceiveDrawPalette(payload) {
        Na__DrawBridge__NotifyTab('na_receive_palette', payload || {});
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__DrawProfile__Bridge__ResolveSelection    = Na__DrawProfile__Bridge__ResolveSelection;
    window.Na__DrawProfile__Bridge__Save                = Na__DrawProfile__Bridge__Save;
    window.Na__DrawProfile__Bridge__CountUsage          = Na__DrawProfile__Bridge__CountUsage;
    window.Na__DrawProfile__Bridge__ApplyLocal          = Na__DrawProfile__Bridge__ApplyLocal;
    window.Na__DrawProfile__Bridge__RevertLocal         = Na__DrawProfile__Bridge__RevertLocal;
    window.Na__DrawProfile__Bridge__RequestPalette      = Na__DrawProfile__Bridge__RequestPalette;
    window.Na__ProfilePathTracer__ReceiveDrawPalette    = Na__ProfilePathTracer__ReceiveDrawPalette;
    window.Na__ProfilePathTracer__ReceiveDrawLocalResult = Na__ProfilePathTracer__ReceiveDrawLocalResult;
    window.Na__ProfilePathTracer__ReceiveDrawSelection  = Na__ProfilePathTracer__ReceiveDrawSelection;
    window.Na__ProfilePathTracer__ReceiveDrawSaveResult = Na__ProfilePathTracer__ReceiveDrawSaveResult;
    window.Na__ProfilePathTracer__ReceiveDrawKeyUsage   = Na__ProfilePathTracer__ReceiveDrawKeyUsage;

    // endregion ----------------------------------------------------------------
})();
