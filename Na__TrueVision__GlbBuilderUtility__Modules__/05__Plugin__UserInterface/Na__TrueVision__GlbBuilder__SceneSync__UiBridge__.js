(function() {
    'use strict';

    // =============================================================================
    // NOBLE ARCHITECTURE - TRUEVISION3D GLB BUILDER UTILITY - SCENE SYNC TAB BRIDGE
    //
    // FILE       : Na__TrueVision__GlbBuilder__SceneSync__UiBridge__.js
    // PURPOSE    : The Scene Sync tab: every SketchUp scene with its switch (all
    //              off by default), its type, what it becomes in TrueVision, how
    //              it stands against the project, Detach, and the sync actions.
    // CREATED    : 19-Oct-2026
    //
    // CONTRACT WITH THE MAIN BRIDGE (a separate IIFE, so only window.* is shared):
    // - Ruby pushes Na__Tvgb__ReceiveSceneSyncStatus(status).
    // - Sync And Push goes through window.Na__Tvgb__RunExportAction, which locks
    //   every action card until Ruby pushes a report with running: false.
    // - The main bridge re-enables every card after each report, model status
    //   and project status; this file wraps those receivers and re-applies its
    //   own locks straight after (as the Point Cloud tab's bridge does).
    //
    // -----------------------------------------------------------------------------
    //
    // DEVELOPMENT LOG:
    // 19-Oct-2026 - Version 2.12.0
    // - Initial Scene Sync tab.
    //
    // =============================================================================


    // -----------------------------------------------------------------------------
    // REGION | State
    // -----------------------------------------------------------------------------

    var naSs = {
        status    : null,     // <-- last Na__Tvgb__ReceiveSceneSyncStatus payload
        busy      : false,    // <-- true from a report with running: true until one without
        armDetach : null      // <-- the pid whose Detach was clicked once, waiting for the second click
    };

    var NA_SS_STATE = {
        upToDate  : { text : 'Synced',                 css : 'upToDate' },
        changed   : { text : 'Changed since sync',     css : 'changed' },
        notSynced : { text : 'Not synced yet',         css : 'changed' },
        frozen    : { text : 'Off, kept in TrueVision', css : 'off' },
        detachedInTrueVision : { text : 'Detached in TrueVision', css : 'off' }
    };

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Helpers
    // -----------------------------------------------------------------------------

    function na__ss__esc(raw) {
        return String(raw === undefined || raw === null ? '' : raw)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function na__ss__el(id) { return document.getElementById(id); }

    function na__ss__text(id, value) {
        var el = na__ss__el(id);
        if (el) { el.textContent = String(value === undefined || value === null ? '' : value); }
    }

    function na__ss__setStatus(text, variant) {
        if (window.Na__Tvgb__SetStatus) { window.Na__Tvgb__SetStatus(text, variant); }
    }

    function na__ss__dispatch(actionId, params) {
        if (!window.sketchup || !window.sketchup.na_tvgb_run_action) {
            na__ss__setStatus('SketchUp bridge unavailable.', 'error');
            return false;
        }
        window.sketchup.na_tvgb_run_action(String(actionId), JSON.stringify(params || {}));
        return true;
    }

    // "2026-10-19T14:11:02+0100" as "19 Oct 2026 14:11", read as written (no Date parsing).
    function na__ss__when(iso) {
        var match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(String(iso || ''));
        if (!match) { return ''; }
        var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return parseInt(match[3], 10) + ' ' + (months[parseInt(match[2], 10) - 1] || match[2]) + ' ' + match[1] + ' ' + match[4] + ':' + match[5];
    }

    // Why a sync cannot run now, or '' when it can.
    function na__ss__blockedReason() {
        var s = naSs.status;
        if (!s)                 { return 'Waiting for SketchUp.'; }
        if (s.readonly)         { return s.problem || 'The Scene Sync settings are read only here.'; }
        if (!s.projectLinked)   { return 'Link this model to a project on the Project tab.'; }
        if (!s.storePath)       { return s.storeMissingWhy || 'The project is not on this computer.'; }
        if (s.storePathProblem) { return s.storePathProblem; }
        if (!s.onCount && !s.frozenCount) { return 'Switch at least one scene on first.'; }
        return '';
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Scene Rows
    // -----------------------------------------------------------------------------

    function na__ss__typeSelect(scene) {
        var s = naSs.status;
        var auto = scene.typeChosen === null || scene.typeChosen === undefined || scene.typeChosen === '';
        var suggested = (s.types || []).filter(function(type) { return type.id === scene.typeSuggested; })[0];
        var options = [{ value : '', label : 'Automatic' + (suggested ? ' (' + suggested.label + ')' : '') }]
            .concat((s.types || []).map(function(type) { return { value : type.id, label : type.label }; }));
        return '<label class="naTvgb__PcField"><span class="naTvgb__PcField__Label">Type</span>'
            + '<select class="naTvgb__Select naTvgb__PcSelect" data-na-ss-input onchange="Na__Tvgb__SsSetType(' + Number(scene.pid) + ', this.value)">'
            + options.map(function(option) {
                return '<option value="' + na__ss__esc(option.value) + '"' + ((auto ? '' : scene.typeChosen) === option.value ? ' selected' : '') + '>' + na__ss__esc(option.label) + '</option>';
            }).join('')
            + '</select></label>';
    }

    function na__ss__sceneHtml(scene) {
        var pid = Number(scene.pid);
        var on  = !!scene.on;
        var lockedOff = !on && !scene.hasCamera;                                // <-- nothing to sync; one that is on stays switchable, so it can be switched off
        var cls = 'naTvgb__PcScene naTvgb__SsScene' + (on ? '' : ' naTvgb__PcScene--off') + (!scene.hasCamera ? ' naTvgb__PcScene--problem' : '');
        var state = NA_SS_STATE[scene.syncState];
        var tags = state ? '<span class="naTvgb__PcTag naTvgb__PcTag--' + state.css + '">' + na__ss__esc(state.text) + '</span>' : '';
        if (!scene.hasCamera) { tags = '<span class="naTvgb__PcTag naTvgb__PcTag--warn">No camera</span>'; }
        var armed = naSs.armDetach === pid;
        var canDetach = !!scene.id && (scene.syncState === 'upToDate' || scene.syncState === 'changed' || scene.syncState === 'frozen' || scene.syncState === 'detachedInTrueVision');
        var detach = canDetach
            ? '<button type="button" class="naTvgb__MiniBtn naTvgb__SsDetach' + (armed ? ' naTvgb__SsDetach--armed' : '') + '" data-na-ss-input'
              + ' title="TrueVision keeps this scene as it was last synced, for good. SketchUp stops sending it."'
              + ' onclick="Na__Tvgb__SsDetach(' + pid + ')">' + (armed ? 'Click Again To Detach' : 'Detach') + '</button>'
            : '';
        var lines = '';
        if (on && scene.summary) { lines += '<p class="naTvgb__SsScene__Summary">' + na__ss__esc(scene.summary) + '</p>'; }
        if (scene.pointCloudSceneId && on) { lines += '<p class="naTvgb__SsScene__Summary">Its point cloud scene lays on it in TrueVision exactly.</p>'; }
        if (scene.syncState === 'frozen') { lines += '<p class="naTvgb__SsScene__Summary">Switched off: TrueVision keeps it as last synced, and its viewports keep working. Switch it on to resume.</p>'; }
        if (scene.syncState === 'detachedInTrueVision') { lines += '<p class="naTvgb__SsScene__Summary">Detached in TrueVision: it is TrueVision\'s own there now, and a sync no longer changes it. Switch it off here, or Detach it here as well.</p>'; }
        if (scene.detachedBefore && !on) { lines += '<p class="naTvgb__SsScene__Summary">Detached before: switching it on starts a new synced scene.</p>'; }
        if (!scene.hasCamera) { lines += '<p class="naTvgb__PcScene__Warn">' + na__ss__esc(scene.summary) + '</p>'; }
        (scene.warnings || []).forEach(function(text) { lines += '<p class="naTvgb__PcScene__Warn">' + na__ss__esc(text) + '</p>'; });
        return '<div class="' + cls + '">'
            + '<div class="naTvgb__PcScene__Head">'
            +   '<input type="checkbox" class="naTvgb__FileRow__Toggle" data-na-ss-input' + (lockedOff ? ' data-na-ss-locked disabled' : '')
            +   ' title="Keep this scene in sync with TrueVision"' + (on ? ' checked' : '') + ' onchange="Na__Tvgb__SsToggle(' + pid + ', this.checked)">'
            +   '<span class="naTvgb__PcScene__Name">' + na__ss__esc(scene.name) + '</span>'
            +   (on && scene.typeLabel ? '<span class="naTvgb__PcScene__Type">' + na__ss__esc(scene.typeLabel) + '</span>' : '')
            +   '<span class="naTvgb__SelectBar__Spacer"></span>' + tags + detach
            + '</div>'
            + (on ? '<div class="naTvgb__PcScene__Fields">' + na__ss__typeSelect(scene) + '</div>' : '')
            + lines
            + '</div>';
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Render
    // -----------------------------------------------------------------------------

    function na__ss__render() {
        var s = naSs.status;
        if (!s) { return; }
        var tab = na__ss__el('naTvgbSsTabButton');
        if (tab) { tab.classList.toggle('naTvgb__TabButton--pcOn', (s.onCount || 0) > 0); }

        na__ss__text('naTvgbSsProject', s.projectLinked ? (s.projectCode || 'Linked') : 'Not linked. Link this model on the Project tab.');
        na__ss__text('naTvgbSsStore', s.storePath
            ? s.storePath + (s.storePathProblem ? '. ' + s.storePathProblem : '')
            : (s.storeMissingWhy || ''));
        na__ss__text('naTvgbSsLast', s.lastSyncedIso ? na__ss__when(s.lastSyncedIso) : 'Not synced yet.');

        var list = na__ss__el('naTvgbSsSceneList');
        var scenes = s.scenes || [];
        if (list) {
            if (s.readonly && s.problem) {
                list.innerHTML = '<div class="naTvgb__Note naTvgb__Note--empty">' + na__ss__esc(s.problem) + '</div>';
            } else if (!scenes.length) {
                list.innerHTML = '<div class="naTvgb__Note naTvgb__Note--empty">This model has no SketchUp scenes. Add scenes in SketchUp (View, Animation, Add Scene) and they appear here.</div>';
            } else {
                list.innerHTML = scenes.map(na__ss__sceneHtml).join('');
            }
        }
        na__ss__text('naTvgbSsSceneCount', scenes.length ? scenes.length + ' scene' + (scenes.length === 1 ? '' : 's') : '');
        na__ss__text('naTvgbSsOnCount', (s.onCount || 0) + ' kept in sync' + (s.frozenCount ? ', ' + s.frozenCount + ' kept as last synced' : ''));
        na__ss__applyLocks();
    }

    function na__ss__applyLocks() {
        var s = naSs.status;
        var busy = naSs.busy;
        var reason = na__ss__blockedReason();
        ['naTvgbSsRunCard', 'naTvgbSsRunPushCard'].forEach(function(cardId) {
            var card = na__ss__el(cardId);
            if (!card) { return; }
            card.disabled = busy || reason !== '';
            card.title = busy ? 'An export is running.' : reason;
        });
        var inputs = document.querySelectorAll('#tab-scenesync [data-na-ss-input], #naTvgbSsAllOff');
        for (var i = 0; i < inputs.length; i += 1) {
            inputs[i].disabled = busy || !!(s && s.readonly) || inputs[i].hasAttribute('data-na-ss-locked');
        }
        ['naTvgbSsFolderBtn', 'naTvgbSsRefreshBtn'].forEach(function(buttonId) {
            var button = na__ss__el(buttonId);
            if (button) { button.disabled = busy; }
        });
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Actions
    // -----------------------------------------------------------------------------

    function Na__Tvgb__SsToggle(pid, on) {
        naSs.armDetach = null;
        na__ss__dispatch('scenesync_set_on', { pid : Number(pid), on : !!on });
    }

    function Na__Tvgb__SsAllOff() {
        var pids = (naSs.status && naSs.status.scenes ? naSs.status.scenes : []).filter(function(scene) { return scene.on; }).map(function(scene) { return scene.pid; });
        if (!pids.length) { return; }
        na__ss__dispatch('scenesync_set_on', { pids : pids, on : false });
    }

    function Na__Tvgb__SsSetType(pid, type) {
        na__ss__dispatch('scenesync_set_type', { pid : Number(pid), type : String(type || '') });
    }

    // Two clicks, three seconds apart at most: detaching cannot be undone from here.
    function Na__Tvgb__SsDetach(pid) {
        if (naSs.armDetach !== Number(pid)) {
            naSs.armDetach = Number(pid);
            na__ss__render();
            window.setTimeout(function() { if (naSs.armDetach === Number(pid)) { naSs.armDetach = null; na__ss__render(); } }, 3000);
            return;
        }
        naSs.armDetach = null;
        na__ss__dispatch('scenesync_detach', { pid : Number(pid) });
    }

    function Na__Tvgb__SsAction(actionId) {
        na__ss__dispatch(actionId, {});
    }

    function Na__Tvgb__SsRun(push) {
        var reason = na__ss__blockedReason();
        if (reason) { na__ss__setStatus(reason, 'warning'); return; }
        if (!push) { na__ss__dispatch('scenesync_sync', {}); return; }
        if (!window.Na__Tvgb__RunExportAction) { na__ss__setStatus('SketchUp bridge unavailable.', 'error'); return; }
        naSs.busy = true;
        na__ss__applyLocks();
        window.Na__Tvgb__RunExportAction('scenesync_sync_push');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Receivers (Ruby pushes, and wraps of the main bridge's)
    // -----------------------------------------------------------------------------

    function Na__Tvgb__ReceiveSceneSyncStatus(status) {
        if (!status) { return; }
        naSs.status = status;
        na__ss__render();
    }

    function na__ss__wrap(name, after) {
        var original = window[name];
        if (typeof original !== 'function' || original.naSsWrapped) { return; }
        var wrapped = function(payload) {
            original(payload);
            try { after(payload); } catch (err) { /* never break the main bridge */ }
        };
        wrapped.naSsWrapped = true;
        window[name] = wrapped;
    }

    // The Export tab's report panel, mirrored here so a sync from this tab
    // reports where it was started.
    function na__ss__mirrorReport(report) {
        var panel = na__ss__el('naTvgbSsReport');
        var body  = na__ss__el('naTvgbSsReportBody');
        var main  = na__ss__el('naTvgbReport');
        if (!panel || !body || !main) { return; }
        var show = main.style.display !== 'none';
        panel.style.display = show ? '' : 'none';
        if (!show) { return; }
        var steps   = na__ss__el('naTvgbReportSteps');
        var summary = na__ss__el('naTvgbReportSummary');
        body.innerHTML = '<div class="naTvgb__Report__Steps">' + (steps ? steps.innerHTML : '') + '</div>'
            + '<div class="naTvgb__Report__Summary">' + na__ss__esc(summary ? summary.textContent : (report && report.message) || '') + '</div>';
    }

    na__ss__wrap('Na__Tvgb__ReceiveReport', function(report) {
        if (report) { naSs.busy = !!report.running; }
        na__ss__mirrorReport(report);
        na__ss__applyLocks();
    });
    na__ss__wrap('Na__Tvgb__ReceiveModelStatus', na__ss__applyLocks);
    na__ss__wrap('Na__Tvgb__ReceiveProjectStatus', na__ss__applyLocks);

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Exports To Window
    // -----------------------------------------------------------------------------

    window.Na__Tvgb__ReceiveSceneSyncStatus = Na__Tvgb__ReceiveSceneSyncStatus;
    window.Na__Tvgb__SsToggle               = Na__Tvgb__SsToggle;
    window.Na__Tvgb__SsAllOff               = Na__Tvgb__SsAllOff;
    window.Na__Tvgb__SsSetType              = Na__Tvgb__SsSetType;
    window.Na__Tvgb__SsDetach               = Na__Tvgb__SsDetach;
    window.Na__Tvgb__SsAction               = Na__Tvgb__SsAction;
    window.Na__Tvgb__SsRun                  = Na__Tvgb__SsRun;

    // endregion -------------------------------------------------------------------

})();
