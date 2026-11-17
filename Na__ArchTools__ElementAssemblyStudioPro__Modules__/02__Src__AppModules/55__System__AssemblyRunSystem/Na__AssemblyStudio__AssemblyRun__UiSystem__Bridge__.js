// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - BRIDGE (Ruby -> JS)
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AssemblyRun__UiSystem__Bridge__.js
// NAMESPACE  : window.na_* functions Ruby calls; the dock's onclick functions
// AUTHOR     : Noble Architecture
// PURPOSE    : The Assembly Run Studio tab's side of the Ruby bridge. Each
//              function parses what Ruby sent and hands it to Na_RunUI; the
//              dock's buttons call straight into Na_RunUI.
// CREATED    : 16-Nov-2026 (V2.7.0)
//
// RUBY -> JS (Na__AssemblyRunSystem::Na__DialogRouter)
//   window.na_receiveRunBootstrap(json)   defaults, option lists, limits, presets
//   window.na_receiveRunLayout(json)      { layout, ok } for the previews
//   window.na_setInitialRunConfig(json)   a run selected or just built
//   window.na_clearCurrentRun()           the selection moved off the run
//   window.na_receiveRunPath(json)        a path measured in the model
//   window.na_runMeasureCancelled()
//   window.na_setRunPathEdit(json)        { active, runId }: the red path line
//   window.na_receiveRunStaged(json)      { ok, edit, root, layout, message }: a
//                                         named edit Ruby made to the description
//                                         (another product, Flip Inside Out; V2.7.2)
//   (window.na_setRunMember / na_clearRunMember are in the MemberBanner file)
//
// NAMING CONVENTION:
// - All custom identifiers use na_ prefix.
//
// =============================================================================

(function () {
    'use strict';

    // HELPER FUNCTION | Parse a Payload and Hand It On (Never Throws at Ruby)
    // ---------------------------------------------------------------
    function na_receive(name, json, handler) {
        var payload;
        try {
            payload = (typeof json === 'string') ? JSON.parse(json) : json;
        } catch (err) {
            console.error('[Na_RunBridge] ' + name + ': unreadable payload', err);
            return;
        }
        if (typeof Na_RunUI === 'undefined') {
            console.warn('[Na_RunBridge] ' + name + ': Na_RunUI is not loaded');
            return;
        }
        try { handler(payload); }
        catch (err) { console.error('[Na_RunBridge] ' + name + ' failed', err); }
    }

    window.na_receiveRunBootstrap = function (json) { na_receive('na_receiveRunBootstrap', json, Na_RunUI.na_receive_bootstrap); };
    window.na_receiveRunLayout    = function (json) { na_receive('na_receiveRunLayout',    json, Na_RunUI.na_receive_layout); };
    window.na_setInitialRunConfig = function (json) { na_receive('na_setInitialRunConfig', json, Na_RunUI.na_receive_run); };
    window.na_receiveRunPath      = function (json) { na_receive('na_receiveRunPath',      json, Na_RunUI.na_receive_path); };
    window.na_setRunPathEdit      = function (json) { na_receive('na_setRunPathEdit',      json, Na_RunUI.na_set_path_edit); };
    window.na_receiveRunStaged    = function (json) { na_receive('na_receiveRunStaged',    json, Na_RunUI.na_receive_staged); };

    window.na_clearCurrentRun = function () {
        if (typeof Na_RunUI !== 'undefined') Na_RunUI.na_clear_run();
    };

    window.na_runMeasureCancelled = function () {
        var button = document.getElementById('na-btn-measure');
        if (button) button.classList.remove('na-btn-measure-active');
        if (typeof window.na_showStatus === 'function') window.na_showStatus('info', 'Path measuring cancelled.');
    };

    // The dock's buttons (onclick in the layout file).
    window.na_createRun        = function () { if (typeof Na_RunUI !== 'undefined') Na_RunUI.na_create(); };
    window.na_updateRun        = function () { if (typeof Na_RunUI !== 'undefined') Na_RunUI.na_update(); };
    window.na_editRunPath      = function () { if (typeof Na_RunUI !== 'undefined') Na_RunUI.na_edit_path(); };
    window.na_newRunDraft      = function () { if (typeof Na_RunUI !== 'undefined') Na_RunUI.na_new(); };
})();
