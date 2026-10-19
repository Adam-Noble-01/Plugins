(function() {
    'use strict';

    // =============================================================================
    // NOBLE ARCHITECTURE - TRUEVISION3D GLB BUILDER UTILITY - POINT CLOUD TAB BRIDGE
    //
    // FILE       : Na__TrueVision__GlbBuilder__PointCloud__UiBridge__.js
    // PURPOSE    : The Point Cloud tab (master switch, readiness, scene list with
    //              sync toggles and export settings, render actions) and the
    //              Export tab's point cloud row, card and note, which show only
    //              while Export Point Clouds is on.
    // CREATED    : 19-Oct-2026
    //
    // CONTRACT WITH THE MAIN BRIDGE (a separate IIFE, so only window.* is shared):
    // - Ruby pushes Na__Tvgb__ReceivePointCloudStatus(status).
    // - Renders go through window.Na__Tvgb__RunExportAction, which sets the main
    //   bridge's running lock on every action card until Ruby pushes a report
    //   with running: false.
    // - The main bridge re-enables every action card after each report, model
    //   status and project status. This file wraps those three receivers and
    //   re-applies its own readiness rules straight after.
    //
    // -----------------------------------------------------------------------------
    //
    // DEVELOPMENT LOG:
    // 19-Oct-2026 - Version 2.11.0
    // - Initial Point Cloud tab.
    //
    // =============================================================================


    // -----------------------------------------------------------------------------
    // REGION | State
    // -----------------------------------------------------------------------------

    var naPc = {
        status : null,      // <-- last Na__Tvgb__ReceivePointCloudStatus payload
        busy   : false      // <-- true from a report with running: true until one without
    };

    var NA_PC_STATE_TEXT = {
        upToDate    : 'Up to date',
        changed     : 'Changed since export',
        notExported : 'Not exported yet',
        unknown     : 'Load the cloud to check'
    };

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Helpers
    // -----------------------------------------------------------------------------

    function na__pc__esc(raw) {
        return String(raw === undefined || raw === null ? '' : raw)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }

    function na__pc__el(id) { return document.getElementById(id); }

    function na__pc__text(id, value) {
        var el = na__pc__el(id);
        if (el) { el.textContent = String(value === undefined || value === null ? '' : value); }
    }

    function na__pc__show(id, visible) {
        var el = na__pc__el(id);
        if (el) { el.hidden = !visible; }
    }

    function na__pc__setStatus(text, variant) {
        if (window.Na__Tvgb__SetStatus) { window.Na__Tvgb__SetStatus(text, variant); }
    }

    function na__pc__dispatch(actionId, params) {
        if (!window.sketchup || !window.sketchup.na_tvgb_run_action) {
            na__pc__setStatus('SketchUp bridge unavailable.', 'error');
            return false;
        }
        window.sketchup.na_tvgb_run_action(String(actionId), JSON.stringify(params || {}));
        return true;
    }

    function na__pc__int(value) {
        return Math.round(Number(value) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    function na__pc__linkedScenes() {
        var status = naPc.status;
        return status && status.scenes ? status.scenes.filter(function(scene) { return scene.status === 'linked'; }) : [];
    }

    // Why a render cannot start now, or '' when it can.
    function na__pc__blockedReason() {
        var s = naPc.status;
        if (!s)                       { return 'Waiting for SketchUp.'; }
        if (!s.enabled)               { return 'Switch Export Point Clouds on first.'; }
        if (!s.viewer || !s.viewer.available) { return (s.viewer && s.viewer.message) || 'The Na Point Cloud Viewer is not available.'; }
        if (!s.projectLinked)         { return 'Link this model to a project on the Project tab.'; }
        if (!s.storePath)             { return s.storeMissingWhy || 'The project is not on this computer.'; }
        if (!s.cloudLoaded)           { return s.cloudLinked ? 'The point cloud is not loaded. Press Reload Point Cloud.' : 'This model has no point cloud.'; }
        if (!s.selectedCount)         { return 'No point cloud scenes are switched on for sync.'; }
        return '';
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Scene Rows
    // -----------------------------------------------------------------------------

    function na__pc__optionsHtml(items, current) {
        return items.map(function(item) {
            return '<option value="' + na__pc__esc(item.value) + '"' + (String(item.value) === String(current) ? ' selected' : '') + '>'
                + na__pc__esc(item.label) + '</option>';
        }).join('');
    }

    function na__pc__fieldsHtml(scene) {
        var s = naPc.status;
        var id = na__pc__esc(scene.id);
        var types = (s.viewTypes || []).map(function(type) { return { value: type.id, label: type.label }; });
        var html = '<label class="naTvgb__PcField"><span class="naTvgb__PcField__Label">Type</span>'
            + '<select class="naTvgb__Select naTvgb__PcSelect" data-na-pc-input onchange="Na__Tvgb__PcSetExport(\'' + id + '\', \'viewType\', this.value)">'
            + na__pc__optionsHtml(types, scene.viewType) + '</select></label>';

        if (scene.projection === 'perspective') {
            var widths = (s.imageWidthPresets || []).slice();
            if (scene.imageWidthPx && widths.indexOf(scene.imageWidthPx) === -1) { widths.push(scene.imageWidthPx); }
            widths.sort(function(a, b) { return a - b; });
            html += '<label class="naTvgb__PcField"><span class="naTvgb__PcField__Label">Image Width</span>'
                + '<select class="naTvgb__Select naTvgb__PcSelect" data-na-pc-input onchange="Na__Tvgb__PcSetExport(\'' + id + '\', \'imageWidthPx\', Number(this.value))">'
                + na__pc__optionsHtml(widths.map(function(w) { return { value: w, label: na__pc__int(w) + ' px' }; }), scene.imageWidthPx) + '</select></label>';
        } else {
            var scales = (s.scalePresets || []).map(function(p) { return { value: p.denominator, label: p.label }; });
            var known = scales.some(function(p) { return Number(p.value) === Number(scene.scale); });
            if (scene.scale && !known) { scales.push({ value: scene.scale, label: (scene.scaleLabel || ('1:' + scene.scale)) + ' (custom)' }); }
            html += '<label class="naTvgb__PcField"><span class="naTvgb__PcField__Label">Scale</span>'
                + '<select class="naTvgb__Select naTvgb__PcSelect" data-na-pc-input onchange="Na__Tvgb__PcSetExport(\'' + id + '\', \'scale\', Number(this.value))">'
                + na__pc__optionsHtml(scales, scene.scale) + '</select></label>';
        }

        var auto = scene.pointSizePx === null || scene.pointSizePx === undefined;
        var sizes = [{ value: 'auto', label: 'Auto (' + (auto ? scene.exportPointSizePx + ' px' : 'from scale') + ')' }];
        for (var n = 1; n <= 16; n += 1) { sizes.push({ value: n, label: n + ' px' }); }
        html += '<label class="naTvgb__PcField"><span class="naTvgb__PcField__Label">Dot Size</span>'
            + '<select class="naTvgb__Select naTvgb__PcSelect" data-na-pc-input onchange="Na__Tvgb__PcSetExport(\'' + id + '\', \'pointSizePx\', this.value === \'auto\' ? null : Number(this.value))">'
            + na__pc__optionsHtml(sizes, auto ? 'auto' : scene.pointSizePx) + '</select></label>';
        return html;
    }

    function na__pc__sceneHtml(scene) {
        var id = na__pc__esc(scene.id);
        var on = scene.selected !== false;
        var cls = 'naTvgb__PcScene' + (on ? '' : ' naTvgb__PcScene--off') + (scene.status !== 'linked' ? ' naTvgb__PcScene--problem' : '');
        var tags = '';
        if (scene.status === 'missing')       { tags += '<span class="naTvgb__PcTag naTvgb__PcTag--error">Missing</span>'; }
        else if (scene.status === 'noCamera') { tags += '<span class="naTvgb__PcTag naTvgb__PcTag--warn">No camera</span>'; }
        else {
            var state = scene.exportState || 'notExported';
            tags += '<span class="naTvgb__PcTag naTvgb__PcTag--' + na__pc__esc(state) + '">' + na__pc__esc(NA_PC_STATE_TEXT[state] || state) + '</span>';
        }
        var detail = scene.projection === 'perspective'
            ? 'Perspective, ' + na__pc__int(scene.imageWidthPx) + ' px wide'
            : (scene.scaleLabel || '') + ', ' + scene.exportPointSizePx + ' px dots';
        var warnings = (scene.warnings || []).map(function(text) {
            return '<p class="naTvgb__PcScene__Warn">' + na__pc__esc(text) + '</p>';
        }).join('');
        return '<div class="' + cls + '">'
            + '<div class="naTvgb__PcScene__Head">'
            +   '<input type="checkbox" class="naTvgb__FileRow__Toggle" data-na-pc-input title="Sync this scene"' + (on ? ' checked' : '')
            +   ' onchange="Na__Tvgb__PcToggleScene(\'' + id + '\', this.checked)">'
            +   '<span class="naTvgb__PcScene__Name">' + na__pc__esc(scene.name) + '</span>'
            +   '<span class="naTvgb__PcScene__Type">' + na__pc__esc(scene.viewTypeLabel || '') + ', ' + na__pc__esc(detail) + '</span>'
            +   '<span class="naTvgb__SelectBar__Spacer"></span>' + tags
            + '</div>'
            + (scene.status === 'missing' ? '' : '<div class="naTvgb__PcScene__Fields">' + na__pc__fieldsHtml(scene) + '</div>')
            + warnings
            + '</div>';
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Render
    // -----------------------------------------------------------------------------

    function na__pc__render() {
        var s = naPc.status;
        if (!s) { return; }

        var toggle = na__pc__el('naTvgbPcEnabled');
        if (toggle) { toggle.checked = !!s.enabled; }
        var master = na__pc__el('naTvgbPcMaster');
        if (master) { master.classList.toggle('naTvgb__PcMaster--on', !!s.enabled); }
        var tab = na__pc__el('naTvgbPcTabButton');
        if (tab) { tab.classList.toggle('naTvgb__TabButton--pcOn', !!s.enabled); }

        // readiness
        var viewer = s.viewer || {};
        na__pc__text('naTvgbPcViewer', viewer.available ? 'Na Point Cloud Viewer ' + (viewer.version || '') : (viewer.message || 'Not available.'));
        na__pc__text('naTvgbPcCloud', s.cloudLoaded ? (s.cloudName || 'Loaded') + ' (loaded)'
            : s.cloudLinked ? (s.cloudName || 'The linked cloud') + ' is linked but not loaded. Press Reload Point Cloud.'
            : 'No point cloud in this model.');
        na__pc__text('naTvgbPcStore', s.storePath ? s.storePath + (s.storeExists ? '' : '  (made by the first export)') : (s.storeMissingWhy || ''));
        na__pc__text('naTvgbPcDatum', s.datumCount > 0
            ? s.datumCount + ' benchmark' + (s.datumCount === 1 ? '' : 's') + ' found. Recorded with every scene.'
            : 'None found. Put the datum benchmark component on the tag 01__Survey__DatumBenchmark to record it with every scene.');

        // scenes
        var list = na__pc__el('naTvgbPcSceneList');
        var scenes = s.scenes || [];
        if (list) {
            if (!s.listOk) {
                list.innerHTML = '<div class="naTvgb__Note naTvgb__Note--empty">' + na__pc__esc(s.listProblem || 'The point cloud scenes could not be read.') + '</div>';
            } else if (!scenes.length) {
                list.innerHTML = '<div class="naTvgb__Note naTvgb__Note--empty">No point cloud scenes yet. In the Na Point Cloud Viewer, open the Scenes tab, '
                    + 'set the cloud up for a SketchUp scene and press Save Settings For Scene. It appears here.</div>';
            } else {
                list.innerHTML = scenes.map(na__pc__sceneHtml).join('');
            }
        }
        var linked = na__pc__linkedScenes();
        na__pc__text('naTvgbPcSceneCount', scenes.length ? scenes.length + ' scene' + (scenes.length === 1 ? '' : 's') : '');
        na__pc__text('naTvgbPcSelectedCount', linked.length ? (s.selectedCount || 0) + ' of ' + linked.length + ' will sync' : '');

        // Export tab: only while the master switch is on
        var on = !!s.enabled;
        na__pc__show('naTvgbPcSummaryRow', on);
        na__pc__show('naTvgbPcExportCard', on);
        na__pc__show('naTvgbPcExportNote', on);
        if (on) {
            var reason = na__pc__blockedReason();
            na__pc__text('naTvgbPcSummary', reason
                ? 'On, but not ready: ' + reason
                : 'On: ' + s.selectedCount + ' scene' + (s.selectedCount === 1 ? '' : 's') + ' render with the project exports.');
            na__pc__text('naTvgbPcExportNote', 'Point clouds are on. Export To Project Folder and Export And Sync To Cloud also render '
                + (s.selectedCount || 0) + ' point cloud scene' + (s.selectedCount === 1 ? '' : 's') + ' (unchanged ones are skipped). '
                + 'Switch Export Point Clouds off on the Point Cloud tab for a model only export.');
        }

        na__pc__applyLocks();
    }

    // Re-applied after every main bridge repaint, which re-enables all cards.
    function na__pc__applyLocks() {
        var s = naPc.status;
        var busy = naPc.busy;
        var reason = na__pc__blockedReason();
        ['naTvgbPcRunCard', 'naTvgbPcRunSyncCard', 'naTvgbPcExportCard'].forEach(function(cardId) {
            var card = na__pc__el(cardId);
            if (!card) { return; }
            card.disabled = busy || reason !== '';
            card.title = busy ? 'An export is running.' : reason;
        });
        var inputs = document.querySelectorAll('#tab-pointcloud [data-na-pc-input], #naTvgbPcEnabled, #naTvgbPcAllOn, #naTvgbPcAllOff');
        for (var i = 0; i < inputs.length; i += 1) {
            inputs[i].disabled = busy || !!(s && s.readonly);
        }
        ['naTvgbPcReloadBtn', 'naTvgbPcPythonBtn', 'naTvgbPcFolderBtn', 'naTvgbPcRefreshBtn'].forEach(function(buttonId) {
            var button = na__pc__el(buttonId);
            if (button) { button.disabled = busy; }
        });
        var reload = na__pc__el('naTvgbPcReloadBtn');
        if (reload && s) { reload.disabled = busy || s.cloudLoaded || !s.cloudLinked; }
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Actions
    // -----------------------------------------------------------------------------

    function Na__Tvgb__PcSetEnabled(checked) {
        na__pc__dispatch('pointcloud_set_enabled', { enabled: !!checked });
    }

    function Na__Tvgb__PcToggleScene(sceneId, selected) {
        na__pc__dispatch('pointcloud_set_scene_selected', { sceneId: String(sceneId), selected: !!selected });
    }

    function Na__Tvgb__PcSetAll(selected) {
        var ids = (naPc.status && naPc.status.scenes ? naPc.status.scenes : []).map(function(scene) { return scene.id; });
        if (!ids.length) { return; }
        na__pc__dispatch('pointcloud_set_scene_selected', { sceneIds: ids, selected: !!selected });
    }

    function Na__Tvgb__PcSetExport(sceneId, key, value) {
        var values = {};
        values[key] = value;
        na__pc__dispatch('pointcloud_set_scene_export', { sceneId: String(sceneId), values: values });
    }

    function Na__Tvgb__PcAction(actionId) {
        na__pc__dispatch(actionId, {});
    }

    // Renders run through the main bridge so every card locks until the report.
    function Na__Tvgb__PcRun(sync) {
        var reason = na__pc__blockedReason();
        if (reason) { na__pc__setStatus(reason, 'warning'); return; }
        if (!window.Na__Tvgb__RunExportAction) { na__pc__setStatus('SketchUp bridge unavailable.', 'error'); return; }
        naPc.busy = true;
        na__pc__applyLocks();
        window.Na__Tvgb__RunExportAction(sync ? 'pointcloud_export_sync' : 'pointcloud_export');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Receivers (Ruby pushes, and wraps of the main bridge's)
    // -----------------------------------------------------------------------------

    function Na__Tvgb__ReceivePointCloudStatus(status) {
        if (!status) { return; }
        naPc.status = status;
        na__pc__render();
    }

    function na__pc__mirrorReport(report) {
        var panel = na__pc__el('naTvgbPcReport');
        var body  = na__pc__el('naTvgbPcReportBody');
        var main  = na__pc__el('naTvgbReport');
        if (!panel || !body || !main) { return; }
        var show = !!(naPc.status && naPc.status.enabled) && main.style.display !== 'none';
        panel.style.display = show ? '' : 'none';
        if (!show) { return; }
        var steps   = na__pc__el('naTvgbReportSteps');
        var summary = na__pc__el('naTvgbReportSummary');
        body.innerHTML = '<div class="naTvgb__Report__Steps">' + (steps ? steps.innerHTML : '') + '</div>'
            + '<div class="naTvgb__Report__Summary">' + na__pc__esc(summary ? summary.textContent : (report && report.message) || '') + '</div>';
    }

    function na__pc__wrap(name, after) {
        var original = window[name];
        if (typeof original !== 'function' || original.naPcWrapped) { return; }
        var wrapped = function(payload) {
            original(payload);
            try { after(payload); } catch (err) { /* never break the main bridge */ }
        };
        wrapped.naPcWrapped = true;
        window[name] = wrapped;
    }

    na__pc__wrap('Na__Tvgb__ReceiveReport', function(report) {
        if (report) { naPc.busy = !!report.running; }
        na__pc__mirrorReport(report);
        na__pc__applyLocks();
    });
    na__pc__wrap('Na__Tvgb__ReceiveModelStatus', na__pc__applyLocks);
    na__pc__wrap('Na__Tvgb__ReceiveProjectStatus', na__pc__applyLocks);

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Exports To Window
    // -----------------------------------------------------------------------------

    window.Na__Tvgb__ReceivePointCloudStatus = Na__Tvgb__ReceivePointCloudStatus;
    window.Na__Tvgb__PcSetEnabled            = Na__Tvgb__PcSetEnabled;
    window.Na__Tvgb__PcToggleScene           = Na__Tvgb__PcToggleScene;
    window.Na__Tvgb__PcSetAll                = Na__Tvgb__PcSetAll;
    window.Na__Tvgb__PcSetExport             = Na__Tvgb__PcSetExport;
    window.Na__Tvgb__PcAction                = Na__Tvgb__PcAction;
    window.Na__Tvgb__PcRun                   = Na__Tvgb__PcRun;

    // endregion -------------------------------------------------------------------

})();
