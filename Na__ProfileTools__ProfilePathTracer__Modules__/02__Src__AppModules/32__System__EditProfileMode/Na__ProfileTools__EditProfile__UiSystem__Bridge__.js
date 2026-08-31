/* =============================================================================
   NA PROFILE TOOLS - EDIT PROFILE MODE - UI SYSTEM - BRIDGE
   =============================================================================
   FILE       : Na__ProfileTools__EditProfile__UiSystem__Bridge__.js
   NAMESPACE  : window.Na__EditProfile__Bridge__Save
                window.Na__EditProfile__Bridge__ReplaceGeometry
                window.Na__EditProfile__Bridge__RenameFile
                window.Na__EditProfile__Bridge__DeleteProfile
                window.Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult
                window.Na__ProfilePathTracer__ReceiveReplaceGeometryResult
                window.Na__ProfilePathTracer__ReceiveRenameProfileFileResult
                window.Na__ProfilePathTracer__ReceiveDeleteProfileResult
   PURPOSE    : JS -> Ruby bridge for the four in-place edits to a library
                file: metadata save, geometry re-capture, on-disk rename, and
                delete.

   DISPATCH CONTRACT
                Every send returns true only when the call actually reached
                Ruby. The panel disables its buttons until a result comes back,
                so a false is its signal to re-enable immediately — otherwise a
                dead click latches the panel forever on a result that is never
                coming.
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
            return true;
        }
        Na__EditBridge__SetStatus('Save bridge is not available (SketchUp not connected).');
        return false;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Replace Geometry Bridge Call
    // -------------------------------------------------------------------------

    // Ruby validates the live selection and only then arms the origin picker, so
    // this send never writes anything on its own — the write happens on the
    // model click that follows.
    function Na__EditProfile__Bridge__ReplaceGeometry(payload) {
        if (Na__EditBridge__HasCallback('na_profilepathtracer_replace_profile_geometry')) {
            Na__EditBridge__SetStatus('Checking SketchUp selection...');
            window.sketchup.na_profilepathtracer_replace_profile_geometry(JSON.stringify(payload || {}));
            return true;
        }
        Na__EditBridge__SetStatus('Geometry re-capture bridge is not available (SketchUp not connected).');
        return false;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Rename Data File Bridge Call
    // -------------------------------------------------------------------------

    // Ruby owns the sanitising, the collision check and the path guard — this
    // sends the name exactly as typed rather than pre-cleaning it, so what the
    // user is told came back from the code that actually touched the disk.
    function Na__EditProfile__Bridge__RenameFile(payload) {
        if (Na__EditBridge__HasCallback('na_profilepathtracer_rename_profile_file')) {
            Na__EditBridge__SetStatus('Renaming profile data file...');
            window.sketchup.na_profilepathtracer_rename_profile_file(JSON.stringify(payload || {}));
            return true;
        }
        Na__EditBridge__SetStatus('Rename bridge is not available (SketchUp not connected).');
        return false;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Delete Profile Bridge Call
    // -------------------------------------------------------------------------

    function Na__EditProfile__Bridge__DeleteProfile(payload) {
        if (Na__EditBridge__HasCallback('na_profilepathtracer_delete_profile')) {
            Na__EditBridge__SetStatus('Deleting profile data file...');
            window.sketchup.na_profilepathtracer_delete_profile(JSON.stringify(payload || {}));
            return true;
        }
        Na__EditBridge__SetStatus('Delete bridge is not available (SketchUp not connected).');
        return false;
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

        Na__EditBridge__NotifyTab('na_receive_save_result', result);
    }

    function Na__ProfilePathTracer__ReceiveReplaceGeometryResult(result) {
        if (!result || typeof result !== 'object') {
            Na__EditBridge__SetStatus('Geometry re-capture returned no result.');
            return;
        }

        Na__EditBridge__SetStatus(result.statusMessage || 'Geometry re-capture finished.');

        if (result.isReplaced && result.profileKey && result.profileRecord) {
            var store = window.Na__ProfileTools__ProfileStore;
            if (store) {
                store.Na__Store__UpdateRecord(result.profileKey, result.profileRecord);
            }
        }

        Na__EditBridge__NotifyTab('na_receive_replace_geometry_result', result);
    }

    // A rename does not change the profile key, so this patches the existing
    // record in place rather than re-bootstrapping. The fresh record carries the
    // new sourceFile, which every later write to this profile is addressed by.
    function Na__ProfilePathTracer__ReceiveRenameProfileFileResult(result) {
        if (!result || typeof result !== 'object') {
            Na__EditBridge__SetStatus('Rename returned no result.');
            return;
        }

        Na__EditBridge__SetStatus(result.statusMessage || 'Rename finished.');

        if (result.isRenamed && result.profileKey && result.profileRecord) {
            var store = window.Na__ProfileTools__ProfileStore;
            if (store) {
                store.Na__Store__UpdateRecord(result.profileKey, result.profileRecord);
            }
        }

        Na__EditBridge__NotifyTab('na_receive_rename_file_result', result);
    }

    // The store is deliberately NOT touched here. Ruby re-sends the whole
    // bootstrap ahead of this result, which rebuilds the profile map from disk —
    // patching a single key on top of that would only re-introduce the record
    // that was just removed.
    function Na__ProfilePathTracer__ReceiveDeleteProfileResult(result) {
        if (!result || typeof result !== 'object') {
            Na__EditBridge__SetStatus('Delete returned no result.');
            return;
        }

        Na__EditBridge__SetStatus(result.statusMessage || 'Delete finished.');
        Na__EditBridge__NotifyTab('na_receive_delete_result', result);
    }

    function Na__EditBridge__NotifyTab(handlerName, result) {
        var tab = window.Na__ProfileTools__EditProfile__Tab;
        if (tab && typeof tab[handlerName] === 'function') {
            tab[handlerName](result);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__EditProfile__Bridge__Save                          = Na__EditProfile__Bridge__Save;
    window.Na__EditProfile__Bridge__ReplaceGeometry               = Na__EditProfile__Bridge__ReplaceGeometry;
    window.Na__EditProfile__Bridge__RenameFile                    = Na__EditProfile__Bridge__RenameFile;
    window.Na__EditProfile__Bridge__DeleteProfile                 = Na__EditProfile__Bridge__DeleteProfile;
    window.Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult  = Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult;
    window.Na__ProfilePathTracer__ReceiveReplaceGeometryResult    = Na__ProfilePathTracer__ReceiveReplaceGeometryResult;
    window.Na__ProfilePathTracer__ReceiveRenameProfileFileResult  = Na__ProfilePathTracer__ReceiveRenameProfileFileResult;
    window.Na__ProfilePathTracer__ReceiveDeleteProfileResult      = Na__ProfilePathTracer__ReceiveDeleteProfileResult;

    // endregion ----------------------------------------------------------------
})();
