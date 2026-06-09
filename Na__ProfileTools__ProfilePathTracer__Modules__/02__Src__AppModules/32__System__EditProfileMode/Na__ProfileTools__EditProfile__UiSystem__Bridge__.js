/* =============================================================================
   NA PROFILE TOOLS - EDIT PROFILE MODE - UI SYSTEM - BRIDGE
   =============================================================================
   FILE       : Na__ProfileTools__EditProfile__UiSystem__Bridge__.js
   NAMESPACE  : window.Na__EditProfile__Bridge__Save
                window.Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult
   PURPOSE    : JS -> Ruby bridge for saving edited profile metadata in-place.
   ============================================================================= */

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Bridge Availability Helpers
    // -------------------------------------------------------------------------

    function Na__EditBridge__HasCallback(name) {
        return !!(window.sketchup && typeof window.sketchup[name] === 'function');
    }

    function Na__EditBridge__SetStatus(message) {
        if (typeof window.Na__ProfilePathTracer__Ui__SetStatusFromBridge === 'function') {
            window.Na__ProfilePathTracer__Ui__SetStatusFromBridge(message);
            return;
        }
        var el = document.getElementById('na-status-message');
        if (el) el.textContent = message || '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Save Bridge Call
    // -------------------------------------------------------------------------

    function Na__EditProfile__Bridge__Save(payload) {
        if (Na__EditBridge__HasCallback('na_profilepathtracer_update_profile_meta')) {
            Na__EditBridge__SetStatus('Saving profile metadata...');
            window.sketchup.na_profilepathtracer_update_profile_meta(JSON.stringify(payload || {}));
            return;
        }
        Na__EditBridge__SetStatus('Save bridge is not available (SketchUp not connected).');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Ruby -> JS Receive Handler
    // -------------------------------------------------------------------------

    function Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult(result) {
        if (!result || typeof result !== 'object') {
            Na__EditBridge__SetStatus('Meta update returned no result.');
            return;
        }

        Na__EditBridge__SetStatus(result.statusMessage || 'Profile metadata updated.');

        if (result.isSaved && result.profileKey && result.profileRecord) {
            var store = window.Na__ProfileTools__ProfileStore;
            if (store) {
                store.Na__Store__UpdateRecord(result.profileKey, result.profileRecord);
            }
        }

        if (window.Na__ProfileTools__EditProfile__Tab &&
            typeof window.Na__ProfileTools__EditProfile__Tab.na_receive_save_result === 'function') {
            window.Na__ProfileTools__EditProfile__Tab.na_receive_save_result(result);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__EditProfile__Bridge__Save                          = Na__EditProfile__Bridge__Save;
    window.Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult  = Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult;

    // endregion ----------------------------------------------------------------
})();
