(function() {
    'use strict';

    // =============================================================================
    // VALEDESIGNSUITE - VALEVISION CLOUD SYNC HTMLDIALOG UI BRIDGE
    //
    // FILE       : Na__ValeVisionCloudSync__UiBridge__.js
    // PURPOSE    : Tab switching, Ruby bridge callbacks, status line, report
    //              rendering, and project path display.
    // =============================================================================


    // -----------------------------------------------------------------------------
    // REGION | Module State
    // -----------------------------------------------------------------------------

    var naVvcsState = {
        isRunning    : false,   // <-- true while a sync action is in progress
        activeTabId  : 'export' // <-- tracks which tab is visible
    };

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Tab Switching
    // -----------------------------------------------------------------------------

    function Na__Vvcs__ShowTab(tabId, buttonElement) {
        var panels  = document.querySelectorAll('.naVvcs__TabPanel');
        var buttons = document.querySelectorAll('.naVvcs__TabButton');

        for (var pi = 0; pi < panels.length; pi += 1) {
            panels[pi].classList.remove('naVvcs__TabPanel--active');
        }
        for (var bi = 0; bi < buttons.length; bi += 1) {
            buttons[bi].classList.remove('naVvcs__TabButton--active');
        }

        var panel = document.getElementById('tab-' + tabId);
        if (panel) {
            panel.classList.add('naVvcs__TabPanel--active');
        }
        if (buttonElement) {
            buttonElement.classList.add('naVvcs__TabButton--active');
        }

        naVvcsState.activeTabId = tabId;
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Footer Status Helper
    // -----------------------------------------------------------------------------

    function na__vvcs__setStatus(text, variant) {
        var el = document.getElementById('naVvcsStatus');
        if (!el) { return; }
        el.textContent = String(text || '');
        el.className   = 'naVvcs__Status naVvcs__Status--' + String(variant || 'info');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | SketchUp Bridge — Standard Command Invocation
    // -----------------------------------------------------------------------------

    function Na__Vvcs__RunCommand(commandId) {
        if (!window.sketchup || !window.sketchup.run_command) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }
        na__vvcs__setStatus('Running: ' + commandId + '...', 'info');
        window.sketchup.run_command(String(commandId));
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | SketchUp Bridge — Sync Action Invocation
    // -----------------------------------------------------------------------------

    function Na__Vvcs__RunSyncAction(actionId) {
        if (naVvcsState.isRunning) {
            na__vvcs__setStatus('A sync action is already in progress.', 'warning');
            return;
        }
        if (!window.sketchup || !window.sketchup.na_vvcs_run_sync_action) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }

        naVvcsState.isRunning = true;
        na__vvcs__setActionButtonsDisabled(true);
        na__vvcs__setStatus('Running sync action: ' + actionId + '...', 'info');

        window.sketchup.na_vvcs_run_sync_action(String(actionId));
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | SketchUp Bridge — Settings Path Actions
    // -----------------------------------------------------------------------------

    function Na__Vvcs__SavePathOverride() {
        if (!window.sketchup || !window.sketchup.na_vvcs_save_path_override) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }
        var input = document.getElementById('naVvcsPathInput');
        var path  = input ? input.value.trim() : '';
        if (!path) {
            na__vvcs__setStatus('Enter a project path to save.', 'warning');
            return;
        }
        window.sketchup.na_vvcs_save_path_override(path);
    }

    function Na__Vvcs__ClearPathOverride() {
        if (!window.sketchup || !window.sketchup.na_vvcs_clear_path_override) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }
        var input = document.getElementById('naVvcsPathInput');
        if (input) { input.value = ''; }
        window.sketchup.na_vvcs_clear_path_override();
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Ruby Push Receivers — Report, Path Status
    // -----------------------------------------------------------------------------

    function Na__Vvcs__ReceiveReport(report) {
        if (!report) { return; }

        // <-- Re-enable buttons when sync completes (running=false or missing)
        if (!report.running) {
            naVvcsState.isRunning = false;
            na__vvcs__setActionButtonsDisabled(false);
        }

        na__vvcs__renderReport(report);
    }

    function Na__Vvcs__ReceivePathStatus(pathData) {
        if (!pathData) { return; }

        var modelNameEl  = document.getElementById('naVvcsModelName');
        var projectRootEl = document.getElementById('naVvcsProjectRoot');
        var derivedRootEl = document.getElementById('naVvcsDerivedRoot');
        var imgCountEl   = document.getElementById('naVvcsImgSceneCount');
        var pathInput    = document.getElementById('naVvcsPathInput');

        if (modelNameEl)  { modelNameEl.textContent  = pathData.model_name  || '\u2014'; }
        if (imgCountEl)   { imgCountEl.textContent   = String(pathData.img_scene_count !== undefined ? pathData.img_scene_count : '\u2014'); }
        if (derivedRootEl) { derivedRootEl.textContent = pathData.derived_root || '\u2014'; }

        if (projectRootEl) {
            projectRootEl.textContent = pathData.active_path || '\u2014';
            if (pathData.has_override) {
                projectRootEl.classList.add('naVvcs__ProjectStatus__Value--override');
                projectRootEl.title = 'Override active';
            } else {
                projectRootEl.classList.remove('naVvcs__ProjectStatus__Value--override');
                projectRootEl.title = '';
            }
        }

        if (pathInput && pathData.override_path) {
            pathInput.value = pathData.override_path;
        }
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Report Rendering
    // -----------------------------------------------------------------------------

    function na__vvcs__renderReport(report) {
        var reportEl  = document.getElementById('naVvcsReport');
        var stepsEl   = document.getElementById('naVvcsReportSteps');
        var summaryEl = document.getElementById('naVvcsReportSummary');

        if (!reportEl) { return; }

        if (report.running) {
            stepsEl.innerHTML  = '<div class="naVvcs__ReportStep">'
                + '<span class="naVvcs__ReportStep__Badge naVvcs__ReportStep__Badge--running">...</span>'
                + '<span class="naVvcs__ReportStep__Name">Working</span>'
                + '<span class="naVvcs__ReportStep__Detail">Please wait, this may take several minutes.</span>'
                + '</div>';
            summaryEl.textContent = '';
            reportEl.style.display = '';
            return;
        }

        var steps = Array.isArray(report.steps) ? report.steps : [];
        if (steps.length === 0 && !report.running) {
            reportEl.style.display = 'none';
            return;
        }

        stepsEl.innerHTML = steps.map(function(step) {
            var badge    = na__vvcs__stepBadgeHtml(step.status);
            var name     = na__vvcs__escHtml(step.name    || '');
            var detail   = na__vvcs__escHtml(step.detail  || '');
            return '<div class="naVvcs__ReportStep">'
                + badge
                + '<span class="naVvcs__ReportStep__Name">'  + name   + '</span>'
                + '<span class="naVvcs__ReportStep__Detail">' + detail + '</span>'
                + '</div>';
        }).join('');

        summaryEl.textContent = na__vvcs__escHtml(report.message || '');
        reportEl.style.display = '';
    }

    function na__vvcs__stepBadgeHtml(status) {
        var cls, label;
        switch (String(status || '').toLowerCase()) {
            case 'ok':
            case 'success':
                cls = 'ok'; label = 'OK'; break;
            case 'error':
            case 'fail':
                cls = 'error'; label = 'ERR'; break;
            case 'skip':
            case 'skipped':
                cls = 'skip'; label = 'SKIP'; break;
            default:
                cls = 'running'; label = '...';
        }
        return '<span class="naVvcs__ReportStep__Badge naVvcs__ReportStep__Badge--' + cls + '">' + label + '</span>';
    }

    function na__vvcs__escHtml(raw) {
        return String(raw)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Action Button State
    // -----------------------------------------------------------------------------

    function na__vvcs__setActionButtonsDisabled(disabled) {
        var cards = document.querySelectorAll('.naVvcs__ActionCard');
        for (var i = 0; i < cards.length; i += 1) {
            cards[i].disabled = disabled;
        }
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Bootstrap — Ready Signal and Window API Surface
    // -----------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        // <-- Signal Ruby that dialog DOM is ready so it can push initial state
        if (window.sketchup && window.sketchup.na_vvcs_dialog_ready) {
            window.sketchup.na_vvcs_dialog_ready();
        }
    });

    window.Na__Vvcs__ShowTab            = Na__Vvcs__ShowTab;
    window.Na__Vvcs__RunCommand         = Na__Vvcs__RunCommand;
    window.Na__Vvcs__RunSyncAction      = Na__Vvcs__RunSyncAction;
    window.Na__Vvcs__SavePathOverride   = Na__Vvcs__SavePathOverride;
    window.Na__Vvcs__ClearPathOverride  = Na__Vvcs__ClearPathOverride;
    window.Na__Vvcs__ReceiveReport      = Na__Vvcs__ReceiveReport;
    window.Na__Vvcs__ReceivePathStatus  = Na__Vvcs__ReceivePathStatus;

    // endregion -------------------------------------------------------------------


    // =============================================================================
    // END OF FILE
    // =============================================================================
})();
