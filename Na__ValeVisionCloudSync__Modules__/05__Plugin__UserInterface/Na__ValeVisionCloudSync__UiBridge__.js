(function() {
    'use strict';

    // =============================================================================
    // VALEDESIGNSUITE - VALEVISION CLOUD SYNC HTMLDIALOG UI BRIDGE
    //
    // FILE       : Na__ValeVisionCloudSync__UiBridge__.js
    // PURPOSE    : Tab switching, Ruby bridge callbacks, status line, report
    //              rendering, and project path display.
    //
    // -----------------------------------------------------------------------------
    //
    // DEVELOPMENT LOG:
    // 25-Jun-2026 - Version 1.0.0
    // - Initial HtmlDialog UI bridge for sync actions and report rendering.
    //
    // 25-Jun-2026 - Version 1.1.0
    // - firstSyncComplete state + na__vvcs__applyButtonLockState(): greys out Update
    //   cards until first successful sync; guards Update actions when locked.
    //
    // =============================================================================


    // -----------------------------------------------------------------------------
    // REGION | Module State
    // -----------------------------------------------------------------------------

    var naVvcsState = {
        isRunning         : false,   // <-- true while a sync action is in progress
        activeTabId       : 'export',// <-- tracks which tab is visible
        firstSyncComplete : false    // <-- true once a full sync has succeeded for this model (unlocks Update cards)
    };

    var NA_VVCS_REQUIRES_SYNC_SELECTOR = '.naVvcs__ActionCard[data-na-requires-sync="true"]'; // <-- The three Update cards

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
        // <-- Update actions are locked until a full Sync Project has succeeded once
        if (actionId !== 'sync_project' && !naVvcsState.firstSyncComplete) {
            na__vvcs__setStatus('Run a full Sync Project To ValeVision 3D first.', 'warning');
            return;
        }
        if (!window.sketchup || !window.sketchup.na_vvcs_run_sync_action) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }

        naVvcsState.isRunning = true;
        na__vvcs__applyButtonLockState();   // <-- Disables all cards while running
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
            na__vvcs__applyButtonLockState();   // <-- Restore lock-aware state (Update cards stay locked until first sync)
        }

        na__vvcs__renderReport(report);
    }

    function Na__Vvcs__ReceivePathStatus(pathData) {
        if (!pathData) { return; }

        naVvcsState.firstSyncComplete = !!pathData.first_sync_complete;   // <-- Drives the Update-card lock
        na__vvcs__applyButtonLockState();

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
            var badge    = na__vvcs__stepBadgeHtml(step);                       // <-- Derive badge from success flag
            var name     = na__vvcs__escHtml(step.label || step.name || '');    // <-- Ruby/Python use 'label'
            var detail   = na__vvcs__escHtml(step.message || step.detail || '').replace(/\n/g, '<br>'); // <-- Multi-line diagnostics render as line breaks
            return '<div class="naVvcs__ReportStep">'
                + badge
                + '<span class="naVvcs__ReportStep__Name">'  + name   + '</span>'
                + '<span class="naVvcs__ReportStep__Detail">' + detail + '</span>'
                + '</div>';
        }).join('');

        summaryEl.textContent = na__vvcs__escHtml(report.message || '');
        reportEl.style.display = '';
    }

    function na__vvcs__stepBadgeHtml(step) {
        // Accept a boolean success flag (Ruby/Python format) or a status string.
        var cls, label;
        var success = (step && typeof step.success === 'boolean') ? step.success : undefined;
        var status  = (step && step.status) ? String(step.status).toLowerCase() : '';

        if (success === true || status === 'ok' || status === 'success') {
            cls = 'ok'; label = 'OK';
        } else if (success === false || status === 'error' || status === 'fail') {
            cls = 'error'; label = 'ERR';
        } else if (status === 'skip' || status === 'skipped') {
            cls = 'skip'; label = 'SKIP';
        } else {
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

    // FUNCTION | Apply Lock-Aware Action Button State
    // ------------------------------------------------------------
    // While a sync runs every card is disabled. Otherwise the primary "Sync
    // Project" card is always enabled, and the three Update cards (tagged with
    // data-na-requires-sync) stay greyed out until a first sync has succeeded.
    // ------------------------------------------------------------
    function na__vvcs__applyButtonLockState() {
        if (naVvcsState.isRunning) {
            na__vvcs__setActionButtonsDisabled(true);   // <-- Everything locked mid-run
            return;
        }

        na__vvcs__setActionButtonsDisabled(false);      // <-- Baseline: all enabled

        var lockUpdates = !naVvcsState.firstSyncComplete;
        var updateCards = document.querySelectorAll(NA_VVCS_REQUIRES_SYNC_SELECTOR);
        for (var i = 0; i < updateCards.length; i += 1) {
            updateCards[i].disabled = lockUpdates;       // <-- Greyed via .naVvcs__ActionCard:disabled
            updateCards[i].title    = lockUpdates ? 'Run a full Sync Project To ValeVision 3D first.' : '';
        }
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Bootstrap — Ready Signal and Window API Surface
    // -----------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        na__vvcs__applyButtonLockState();   // <-- Start with Update cards locked until Ruby pushes the real state
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
