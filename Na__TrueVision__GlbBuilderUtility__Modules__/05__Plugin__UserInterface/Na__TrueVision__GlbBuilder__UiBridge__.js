(function() {
    'use strict';

    // =============================================================================
    // NOBLE ARCHITECTURE - TRUEVISION3D GLB BUILDER UTILITY - HTMLDIALOG UI BRIDGE
    //
    // FILE       : Na__TrueVision__GlbBuilder__UiBridge__.js
    // PURPOSE    : Tab switching, Ruby bridge callbacks, status line, export
    //              manifest rendering, and badge-driven report rendering.
    // CREATED    : 19-Sep-2026
    //
    // -----------------------------------------------------------------------------
    //
    // DEVELOPMENT LOG:
    // 19-Sep-2026 - Version 2.8.0
    // - Initial bridge, ported from the ValeVision Cloud Sync UI bridge pattern.
    // - Manifest is rendered client-side from JSON pushed by Ruby so a rescan
    //   never needs a full set_html round trip.
    //
    // =============================================================================


    // -----------------------------------------------------------------------------
    // REGION | Module State
    // -----------------------------------------------------------------------------

    var naTvgbState = {
        isRunning        : false,     // <-- true while an export action is in progress
        activeTabId      : 'export',  // <-- tracks which tab is visible
        canExportModel   : false,     // <-- model holds at least one exportable tag group
        canExportSitePlan: false      // <-- model holds at least one site plan tag (71-75)
    };

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Brand Logo Fallback
    // -----------------------------------------------------------------------------

    // FUNCTION | Swap To The Bundled Logo When The Remote Asset Fails
    // ------------------------------------------------------------
    // The header pulls the canonical logo from noble-architecture.com. If the
    // machine is offline the bundled 06__Assets copy takes over; if that is also
    // missing the image is hidden rather than showing a broken-image glyph.
    // ---------------------------------------------------------------
    function Na__Tvgb__HandleLogoError(imgElement) {
        if (!imgElement) { return; }

        var fallback = imgElement.getAttribute('data-na-logo-fallback');
        if (fallback && imgElement.src !== fallback) {
            imgElement.removeAttribute('data-na-logo-fallback');   // <-- One retry only
            imgElement.src = fallback;
            return;
        }

        imgElement.style.display = 'none';
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Tab Switching
    // -----------------------------------------------------------------------------

    function Na__Tvgb__ShowTab(tabId, buttonElement) {
        var panels  = document.querySelectorAll('.naTvgb__TabPanel');
        var buttons = document.querySelectorAll('.naTvgb__TabButton');

        for (var pi = 0; pi < panels.length; pi += 1) {
            panels[pi].classList.remove('naTvgb__TabPanel--active');
        }
        for (var bi = 0; bi < buttons.length; bi += 1) {
            buttons[bi].classList.remove('naTvgb__TabButton--active');
        }

        var panel = document.getElementById('tab-' + tabId);
        if (panel) {
            panel.classList.add('naTvgb__TabPanel--active');
        }
        if (buttonElement) {
            buttonElement.classList.add('naTvgb__TabButton--active');
        }

        naTvgbState.activeTabId = tabId;
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Footer Status Helper
    // -----------------------------------------------------------------------------

    function na__tvgb__setStatus(text, variant) {
        var el = document.getElementById('naTvgbStatus');
        if (!el) { return; }
        el.textContent = String(text || '');
        el.className   = 'naTvgb__Status naTvgb__Status--' + String(variant || 'info');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Export Options
    // -----------------------------------------------------------------------------

    // FUNCTION | Grey Out The Indexed-Materials Row When Materials Are Off
    // ---------------------------------------------------------------
    function Na__Tvgb__ToggleMaterialDependency() {
        var exportMaterials = document.getElementById('naTvgbExportMaterials');
        var indexedGroup    = document.getElementById('naTvgbIndexedGroup');
        if (!exportMaterials || !indexedGroup) { return; }

        if (exportMaterials.checked) {
            indexedGroup.classList.remove('naTvgb__OptionRow--locked');
        } else {
            indexedGroup.classList.add('naTvgb__OptionRow--locked');
        }
    }

    // HELPER FUNCTION | Read The Current Export Option Set
    // ---------------------------------------------------------------
    function na__tvgb__collectExportParams() {
        var downscaleTextures = na__tvgb__isChecked('naTvgbDownscaleTextures');
        var exportMaterials   = na__tvgb__isChecked('naTvgbExportMaterials');
        var indexedOnly       = na__tvgb__isChecked('naTvgbExportIndexedOnly');

        var materialExportMode = 'no_materials';
        if (exportMaterials && indexedOnly) {
            materialExportMode = 'indexed_only';
        } else if (exportMaterials && !indexedOnly) {
            materialExportMode = 'all_materials';
        }

        return {
            selectionOnly      : false,
            downscaleTextures  : downscaleTextures,
            materialExportMode : materialExportMode
        };
    }

    function na__tvgb__isChecked(elementId) {
        var el = document.getElementById(elementId);
        return !!(el && el.checked);
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | SketchUp Bridge - Export Action Invocation
    // -----------------------------------------------------------------------------

    function Na__Tvgb__RunExportAction(actionId) {
        if (naTvgbState.isRunning) {
            na__tvgb__setStatus('An export action is already in progress.', 'warning');
            return;
        }

        if (actionId === 'export_model' && !naTvgbState.canExportModel) {
            na__tvgb__setStatus('Nothing to export - no entities found on valid tag ranges.', 'warning');
            return;
        }
        if (actionId === 'export_site_plan' && !naTvgbState.canExportSitePlan) {
            na__tvgb__setStatus('No site plan tags (71-75) in this model.', 'warning');
            return;
        }

        var needsProject = (actionId === 'export_to_project' || actionId === 'export_and_sync');
        if (needsProject && !naTvgbProject.linked) {
            na__tvgb__setStatus('Link this model to a project first, on the Project tab.', 'warning');
            return;
        }
        if (needsProject && !naTvgbProject.targetFolder) {
            na__tvgb__setStatus('Choose a design phase folder on the Project tab first.', 'warning');
            return;
        }

        if (!window.sketchup || !window.sketchup.na_tvgb_run_action) {
            na__tvgb__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }

        // A target folder that already holds GLBs is confirmed before anything is written
        if (needsProject && naTvgbProject.targetGlbCount > 0) {
            na__tvgb__showConfirm({
                title:       'Overwrite this scheme?',
                text:        naTvgbProject.targetFolder + ' already holds ' + naTvgbProject.targetGlbCount
                             + ' GLB file(s). They will be moved into that folder\'s 00__Archive before the new export is written.',
                detail:      naTvgbProject.targetFolder,
                acceptLabel: 'Archive And Export'
            }, function() {
                na__tvgb__sendExportAction(actionId);
            });
            return;
        }

        na__tvgb__sendExportAction(actionId);
    }

    // HELPER FUNCTION | Send An Export Action With The Current Option Set
    // ------------------------------------------------------------
    function na__tvgb__sendExportAction(actionId) {
        var params = na__tvgb__collectExportParams();
        params.confirmedOverwrite = true;      // <-- The UI has already asked, where asking was needed

        naTvgbState.isRunning = true;
        na__tvgb__applyButtonLockState();       // <-- Disables all cards while running
        na__tvgb__setStatus('Running: ' + actionId.split('_').join(' ') + '...', 'info');

        window.sketchup.na_tvgb_run_action(String(actionId), JSON.stringify(params));
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Ruby Push Receivers - Report and Model Status
    // -----------------------------------------------------------------------------

    function Na__Tvgb__ReceiveReport(report) {
        if (!report) { return; }

        // <-- Re-enable buttons when the action completes (running=false or missing)
        if (!report.running) {
            naTvgbState.isRunning = false;
            na__tvgb__applyButtonLockState();
        }

        na__tvgb__renderReport(report);
    }

    function Na__Tvgb__ReceiveModelStatus(status) {
        if (!status) { return; }

        naTvgbState.canExportModel    = !!status.can_export_model;
        naTvgbState.canExportSitePlan = !!status.can_export_site_plan;
        na__tvgb__applyButtonLockState();

        na__tvgb__setText('naTvgbModelName',     status.model_name);
        na__tvgb__setText('naTvgbProjectPrefix', status.project_prefix);
        na__tvgb__setText('naTvgbStoreyCount',   na__tvgb__describeStoreys(status));
        na__tvgb__setText('naTvgbSitePlanCount', status.site_plan_tag_count);

        na__tvgb__setText('naTvgbExcludedCount',  status.excluded_tag_count);
        na__tvgb__setText('naTvgbLinetypeCount',  status.linetype_tag_count);
        na__tvgb__setText('naTvgbVerboseLogging', status.verbose_logging  ? 'Enabled' : 'Disabled');
        na__tvgb__setText('naTvgbLogFileEnabled', status.log_file_enabled ? 'Enabled' : 'Disabled');

        na__tvgb__renderManifest(status);
    }

    function na__tvgb__describeStoreys(status) {
        var keys = Number(status.storey_count || 0);
        if (keys === 0) { return 'None (flat model)'; }

        var containers = Number(status.storey_container_count || 0);
        return keys + ' key(s), ' + containers + ' container(s)';
    }

    function na__tvgb__setText(elementId, value) {
        var el = document.getElementById(elementId);
        if (!el) { return; }

        var text = (value === undefined || value === null || value === '') ? '—' : String(value);
        el.textContent = text;
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Export Manifest Rendering
    // -----------------------------------------------------------------------------

    function na__tvgb__renderManifest(status) {
        var bodyEl  = document.getElementById('naTvgbManifestBody');
        var countEl = document.getElementById('naTvgbManifestCount');
        if (!bodyEl) { return; }

        var totalFiles = Number(status.total_file_count || 0);
        if (countEl) {
            countEl.textContent = totalFiles === 0 ? 'Nothing to export' : totalFiles + ' GLB files';
        }

        var html = '';

        // Advisory notes first, in the order Ruby supplied them
        var notes = Array.isArray(status.notes) ? status.notes : [];
        for (var ni = 0; ni < notes.length; ni += 1) {
            html += na__tvgb__noteHtml(notes[ni]);
        }

        // Then the file groups
        var groups = Array.isArray(status.groups) ? status.groups : [];
        for (var gi = 0; gi < groups.length; gi += 1) {
            html += na__tvgb__groupHtml(groups[gi]);
        }

        bodyEl.innerHTML = html;
    }

    function na__tvgb__noteHtml(note) {
        if (!note) { return ''; }

        var variant = na__tvgb__escHtml(note.variant || 'empty');
        var title   = note.title ? '<strong>' + na__tvgb__escHtml(note.title) + '</strong> ' : '';
        var text    = na__tvgb__escHtml(note.text || '');

        return '<div class="naTvgb__Note naTvgb__Note--' + variant + '">' + title + text + '</div>';
    }

    function na__tvgb__groupHtml(group) {
        if (!group) { return ''; }

        var rows = Array.isArray(group.rows) ? group.rows : [];
        var rowsHtml = '';
        for (var ri = 0; ri < rows.length; ri += 1) {
            rowsHtml += na__tvgb__fileRowHtml(rows[ri]);
        }

        // Flat groups render as bare rows; named groups get a collapsible block
        if (!group.label) {
            return rowsHtml;
        }

        var icon  = group.icon ? na__tvgb__escHtml(group.icon) + ' ' : '';
        var count = group.count_label ? '<span class="naTvgb__StoreyBlock__Count">' + na__tvgb__escHtml(group.count_label) + '</span>' : '';

        return '<details class="naTvgb__StoreyBlock" open>'
            + '<summary class="naTvgb__StoreyBlock__Heading">'
            + '<span class="naTvgb__StoreyBlock__HeadingText">' + icon + na__tvgb__escHtml(group.label) + '</span>'
            + count
            + '</summary>'
            + rowsHtml
            + '</details>';
    }

    function na__tvgb__fileRowHtml(row) {
        if (!row) { return ''; }

        return '<div class="naTvgb__FileRow">'
            + '<span class="naTvgb__FileRow__Name">'  + na__tvgb__escHtml(row.name || '') + '</span>'
            + '<span class="naTvgb__FileRow__Count">' + na__tvgb__escHtml(row.meta || '') + '</span>'
            + '</div>';
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Report Rendering
    // -----------------------------------------------------------------------------

    function na__tvgb__renderReport(report) {
        var reportEl  = document.getElementById('naTvgbReport');
        var stepsEl   = document.getElementById('naTvgbReportSteps');
        var summaryEl = document.getElementById('naTvgbReportSummary');

        if (!reportEl || !stepsEl || !summaryEl) { return; }

        if (report.running) {
            stepsEl.innerHTML = '<div class="naTvgb__ReportStep">'
                + '<span class="naTvgb__ReportStep__Badge naTvgb__ReportStep__Badge--running">...</span>'
                + '<span class="naTvgb__ReportStep__Name">Working</span>'
                + '<span class="naTvgb__ReportStep__Detail">Please wait, a large model can take several minutes.</span>'
                + '</div>';
            summaryEl.textContent  = '';
            reportEl.style.display = '';
            return;
        }

        var steps = Array.isArray(report.steps) ? report.steps : [];
        if (steps.length === 0) {
            reportEl.style.display = 'none';
            return;
        }

        stepsEl.innerHTML = steps.map(function(step) {
            var badge  = na__tvgb__stepBadgeHtml(step);
            var name   = na__tvgb__escHtml(step.label || step.name || '');
            var detail = na__tvgb__escHtml(step.message || step.detail || '').split('\n').join('<br>');
            return '<div class="naTvgb__ReportStep">'
                + badge
                + '<span class="naTvgb__ReportStep__Name">'   + name   + '</span>'
                + '<span class="naTvgb__ReportStep__Detail">' + detail + '</span>'
                + '</div>';
        }).join('');

        summaryEl.textContent  = String(report.message || '');
        reportEl.style.display = '';
    }

    function na__tvgb__stepBadgeHtml(step) {
        // Accept a boolean success flag (Ruby format) or a status string.
        var cls, label;
        var success = (step && typeof step.success === 'boolean') ? step.success : undefined;
        var status  = (step && step.status) ? String(step.status).toLowerCase() : '';

        if (success === true || status === 'ok' || status === 'success') {
            cls = 'ok';      label = 'OK';
        } else if (success === false || status === 'error' || status === 'fail') {
            cls = 'error';   label = 'ERR';
        } else if (status === 'skip' || status === 'skipped') {
            cls = 'skip';    label = 'SKIP';
        } else {
            cls = 'running'; label = '...';
        }
        return '<span class="naTvgb__ReportStep__Badge naTvgb__ReportStep__Badge--' + cls + '">' + label + '</span>';
    }

    function na__tvgb__escHtml(raw) {
        return String(raw)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Action Button State
    // -----------------------------------------------------------------------------

    function na__tvgb__setActionButtonsDisabled(disabled) {
        var cards = document.querySelectorAll('.naTvgb__ActionCard');
        for (var i = 0; i < cards.length; i += 1) {
            cards[i].disabled = disabled;
        }
    }

    // FUNCTION | Apply Capability-Aware Action Button State
    // ------------------------------------------------------------
    // While an export runs every card is disabled. Otherwise each card is
    // enabled only when the model actually supports it - a model with no
    // site plan tags keeps that card greyed out, with the reason on hover.
    // ------------------------------------------------------------
    function na__tvgb__applyButtonLockState() {
        var running = naTvgbState.isRunning;        // <-- A run locks everything, on top of the capability rules

        na__tvgb__setActionButtonsDisabled(running);                        // <-- Baseline for every action card

        na__tvgb__lockCard(
            'naTvgbExportModelCard',
            running || !naTvgbState.canExportModel,
            'No entities found on valid tag ranges.'
        );
        na__tvgb__lockCard(
            'naTvgbExportSitePlanCard',
            running || !naTvgbState.canExportSitePlan,
            'No site plan tags (71-75) in this model.'
        );

        // Project-dependent cards: need a link, a target folder, and something to export
        var noProject   = !naTvgbProject.linked;
        var noTarget    = !naTvgbProject.targetFolder;
        var projectWhy  = noProject ? 'Link this model to a project on the Project tab.'
                        : noTarget  ? 'Choose a design phase folder on the Project tab.'
                        : !naTvgbState.canExportModel ? 'No entities found on valid tag ranges.'
                        : '';

        na__tvgb__lockCard('naTvgbExportProjectCard', running || projectWhy !== '', projectWhy);
        na__tvgb__lockCard('naTvgbExportSyncCard',    running || projectWhy !== '', projectWhy);

        na__tvgb__lockCard('naTvgbPushCard',     running || noProject, 'Link this model to a project first.');
        na__tvgb__lockCard('naTvgbDryRunCard',   running || noProject, 'Link this model to a project first.');
        na__tvgb__lockCard('naTvgbPipelineCard', running || noProject, 'Link this model to a project first.');

        // Plain buttons are locked by the same rules - a long export must not
        // leave Unlink or Duplicate clickable underneath it.
        na__tvgb__lockButton('naTvgbUnlinkBtn',    running || noProject);
        na__tvgb__lockButton('naTvgbDuplicateBtn', running || noProject || !naTvgbProject.selectedFolder);

        na__tvgb__updateProjectCardDescription();
    }

    function na__tvgb__lockButton(elementId, shouldLock) {
        var el = document.getElementById(elementId);
        if (el) { el.disabled = shouldLock; }
    }

    // HELPER FUNCTION | Name The Destination On The Export-To-Project Card
    // ------------------------------------------------------------
    function na__tvgb__updateProjectCardDescription() {
        var el = document.getElementById('naTvgbExportProjectDesc');
        if (!el) { return; }

        if (naTvgbProject.linked && naTvgbProject.targetFolder) {
            el.textContent = 'Write straight into ' + naTvgbProject.targetFolder
                + ' for project ' + naTvgbProject.code + ', no folder picker.';
        } else {
            el.textContent = 'Write straight into this model\'s design phase folder in the project portal, no folder picker.';
        }
    }

    function na__tvgb__lockCard(elementId, shouldLock, reason) {
        var card = document.getElementById(elementId);
        if (!card) { return; }

        card.disabled = shouldLock;
        card.title    = shouldLock ? reason : '';
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Project Link - State
    // -----------------------------------------------------------------------------

    var naTvgbProject = {
        linked         : false,   // <-- model carries a valid project code
        code           : '',
        targetFolder   : '',
        targetGlbCount : 0,       // <-- drives the overwrite confirmation
        selectedFolder : '',      // <-- scheme row the user has highlighted
        phases         : [],      // <-- canonical phase catalogue from Ruby
        folders        : [],      // <-- folders that exist on disk
        portalFound    : false
    };

    var NA_TVGB_PROJECT_CODE_PATTERN = /^[A-Z]{2}[0-9]{2}$/;

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Project Link - Modal
    // -----------------------------------------------------------------------------

    function Na__Tvgb__OpenProjectLinkModal() {
        var modal = document.getElementById('naTvgbProjectModal');
        var input = document.getElementById('naTvgbProjectCodeInput');
        if (!modal) { return; }

        // Already open: leave the field and any feedback alone. Ruby re-pushes the
        // project status after a failed lookup, and that must not wipe the error
        // message the user still needs to read.
        if (!modal.hidden) {
            na__tvgb__syncCodeConfirmState();
            return;
        }

        if (input) {
            input.value = naTvgbProject.code || '';
        }
        na__tvgb__setModalFeedback('Two letters and two digits, such as RB05 or EB03.', 'info');
        modal.hidden = false;

        if (input) { input.focus(); input.select(); }
        na__tvgb__syncCodeConfirmState();
    }

    // FUNCTION | Clear The Prompt And Keep Exporting Without A Project
    // ------------------------------------------------------------
    // Tells Ruby to record the choice on the model so the prompt does not
    // reappear every time the dialog opens.
    // ------------------------------------------------------------
    function Na__Tvgb__DismissProjectModal() {
        na__tvgb__hideElement('naTvgbProjectModal');

        if (window.sketchup && window.sketchup.na_tvgb_run_action) {
            window.sketchup.na_tvgb_run_action('dismiss_project_prompt', '{}');
        }
    }

    function Na__Tvgb__SubmitProjectCode() {
        var input = document.getElementById('naTvgbProjectCodeInput');
        var code  = input ? na__tvgb__normaliseCode(input.value) : '';

        if (!NA_TVGB_PROJECT_CODE_PATTERN.test(code)) {
            na__tvgb__setModalFeedback('Enter two letters and two digits, such as RB05.', 'error');
            return;
        }
        if (!window.sketchup || !window.sketchup.na_tvgb_run_action) {
            na__tvgb__setModalFeedback('SketchUp bridge unavailable.', 'error');
            return;
        }

        na__tvgb__setModalFeedback('Looking up ' + code + ' in the project portal...', 'info');
        window.sketchup.na_tvgb_run_action('link_project', JSON.stringify({ projectCode: code }));
    }

    function Na__Tvgb__HandleCodeInput() {
        var input = document.getElementById('naTvgbProjectCodeInput');
        if (!input) { return; }

        var normalised = na__tvgb__normaliseCode(input.value);
        if (input.value !== normalised) { input.value = normalised; }

        na__tvgb__syncCodeConfirmState();
    }

    function Na__Tvgb__HandleCodeKeydown(event) {
        if (!event) { return; }
        if (event.key === 'Enter')  { Na__Tvgb__SubmitProjectCode(); }
        if (event.key === 'Escape') { Na__Tvgb__DismissProjectModal(); }
    }

    function na__tvgb__normaliseCode(raw) {
        return String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 4);
    }

    function na__tvgb__syncCodeConfirmState() {
        var input  = document.getElementById('naTvgbProjectCodeInput');
        var button = document.getElementById('naTvgbProjectModalConfirm');
        if (!input || !button) { return; }

        button.disabled = !NA_TVGB_PROJECT_CODE_PATTERN.test(na__tvgb__normaliseCode(input.value));
    }

    function na__tvgb__setModalFeedback(text, variant) {
        var el = document.getElementById('naTvgbProjectModalFeedback');
        if (!el) { return; }

        el.textContent = String(text || '');
        el.className   = 'naTvgb__Modal__Feedback naTvgb__Modal__Feedback--' + String(variant || 'info');
    }

    // FUNCTION | Ruby Push - Result Of A Project Code Lookup
    // ------------------------------------------------------------
    function Na__Tvgb__ReceiveProjectLinkResult(result) {
        if (!result) { return; }

        if (result.success) {
            na__tvgb__hideElement('naTvgbProjectModal');
            return;
        }
        na__tvgb__setModalFeedback(result.message || 'Could not link that project code.', 'error');
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Generic Confirmation Modal
    // -----------------------------------------------------------------------------

    var naTvgbPendingConfirm = null;   // <-- function run when the user accepts

    // FUNCTION | Ask The User To Confirm, Then Run The Supplied Action
    // ------------------------------------------------------------
    function na__tvgb__showConfirm(options, onAccept) {
        var modal = document.getElementById('naTvgbConfirmModal');
        if (!modal) { onAccept(); return; }          // <-- No modal in the DOM: do not block the user

        na__tvgb__setText2('naTvgbConfirmTitle', options.title || 'Are you sure?');
        na__tvgb__setText2('naTvgbConfirmText',  options.text  || '');

        var detailEl = document.getElementById('naTvgbConfirmDetail');
        if (detailEl) {
            detailEl.textContent = options.detail || '';
            detailEl.hidden      = !options.detail;
        }

        var acceptBtn = document.getElementById('naTvgbConfirmAccept');
        if (acceptBtn) {
            acceptBtn.textContent = options.acceptLabel || 'Continue';
            acceptBtn.className   = 'naTvgb__Btn ' + (options.danger === false ? 'naTvgb__Btn--primary' : 'naTvgb__Btn--danger');
        }

        naTvgbPendingConfirm = onAccept;
        modal.hidden = false;
    }

    function Na__Tvgb__CloseConfirmModal() {
        na__tvgb__hideElement('naTvgbConfirmModal');
        naTvgbPendingConfirm = null;
    }

    function Na__Tvgb__AcceptConfirmModal() {
        var action = naTvgbPendingConfirm;
        na__tvgb__hideElement('naTvgbConfirmModal');
        naTvgbPendingConfirm = null;

        if (typeof action === 'function') { action(); }
    }

    function na__tvgb__setText2(elementId, text) {
        var el = document.getElementById(elementId);
        if (el) { el.textContent = String(text || ''); }
    }

    function na__tvgb__hideElement(elementId) {
        var el = document.getElementById(elementId);
        if (el) { el.hidden = true; }
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Project Tab - Actions
    // -----------------------------------------------------------------------------

    function Na__Tvgb__RunProjectAction(actionId) {
        if (naTvgbState.isRunning) {
            na__tvgb__setStatus('An action is already in progress.', 'warning');
            return;
        }
        if (!window.sketchup || !window.sketchup.na_tvgb_run_action) {
            na__tvgb__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }

        if (actionId !== 'save_portal_root' && !naTvgbProject.linked) {
            na__tvgb__setStatus('Link this model to a project first.', 'warning');
            return;
        }

        var params = {
            phaseId:        na__tvgb__selectedPhaseId(),
            selectedFolder: naTvgbProject.selectedFolder,
            portalRoot:     na__tvgb__readValue('naTvgbPortalInput')
        };

        if (actionId === 'duplicate_scheme' && !naTvgbProject.selectedFolder) {
            na__tvgb__setStatus('Select the scheme you want to duplicate first.', 'warning');
            return;
        }

        na__tvgb__dispatch(actionId, params);
    }

    // FUNCTION | Highlight A Scheme Folder And Make It The Export Target
    // ------------------------------------------------------------
    function Na__Tvgb__SelectScheme(folderName) {
        naTvgbProject.selectedFolder = String(folderName || '');
        na__tvgb__renderSchemeList();

        na__tvgb__dispatch('set_target_folder', { targetFolder: naTvgbProject.selectedFolder });
    }

    function Na__Tvgb__ConfirmUnlinkProject() {
        if (!naTvgbProject.linked) {
            na__tvgb__setStatus('This model is not linked to a project.', 'info');
            return;
        }

        na__tvgb__showConfirm({
            title:       'Unlink this model?',
            text:        'The model will forget project ' + naTvgbProject.code + '. Nothing on disk or in R2 is touched, and you can link it again at any time.',
            acceptLabel: 'Unlink'
        }, function() {
            na__tvgb__dispatch('unlink_project', {});
        });
    }

    function na__tvgb__dispatch(actionId, params) {
        naTvgbState.isRunning = true;
        na__tvgb__applyButtonLockState();
        na__tvgb__setStatus('Running: ' + String(actionId).split('_').join(' ') + '...', 'info');

        window.sketchup.na_tvgb_run_action(String(actionId), JSON.stringify(params || {}));
    }

    function na__tvgb__readValue(elementId) {
        var el = document.getElementById(elementId);
        return el ? String(el.value || '').trim() : '';
    }

    function na__tvgb__selectedPhaseId() {
        var select = document.getElementById('naTvgbNewPhaseSelect');
        return select ? String(select.value || '') : '';
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Project Tab - Rendering
    // -----------------------------------------------------------------------------

    function Na__Tvgb__ReceiveProjectStatus(status) {
        if (!status) { return; }

        // Ruby pushes the project status at the end of every project action, and
        // several of those push no report at all. Clearing the running flag here
        // is what unlocks the UI after, say, creating a folder.
        naTvgbState.isRunning = false;

        naTvgbProject.linked         = !!status.linked;
        naTvgbProject.code           = status.project_code || '';
        naTvgbProject.targetFolder   = status.target_folder || '';
        naTvgbProject.targetGlbCount = Number(status.target_glb_count || 0);
        naTvgbProject.phases         = Array.isArray(status.phases)  ? status.phases  : [];
        naTvgbProject.folders        = Array.isArray(status.folders) ? status.folders : [];
        naTvgbProject.portalFound    = !!status.portal_found;

        if (!naTvgbProject.selectedFolder || !na__tvgb__folderExists(naTvgbProject.selectedFolder)) {
            naTvgbProject.selectedFolder = naTvgbProject.targetFolder;
        }

        na__tvgb__renderProjectCard(status);
        na__tvgb__renderPhaseSelect();
        na__tvgb__renderSchemeList();
        na__tvgb__applyButtonLockState();

        if (status.should_prompt) {
            Na__Tvgb__OpenProjectLinkModal();
        } else if (status.linked) {
            na__tvgb__hideElement('naTvgbProjectModal');   // <-- Linked: the prompt has no reason to stay open
        }
    }

    function na__tvgb__folderExists(folderName) {
        for (var i = 0; i < naTvgbProject.folders.length; i += 1) {
            if (naTvgbProject.folders[i].folder_name === folderName) { return true; }
        }
        return false;
    }

    function na__tvgb__renderProjectCard(status) {
        var card = document.getElementById('naTvgbProjectCard');
        if (card) {
            card.className = 'naTvgb__ProjectCard naTvgb__ProjectCard--' + (status.linked ? 'linked' : 'unlinked');
        }

        na__tvgb__setText('naTvgbProjectCode',   status.linked ? status.project_code : '—');
        na__tvgb__setText('naTvgbProjectName',   status.linked ? (status.project_name || status.project_folder) : 'Not linked to a project');
        na__tvgb__setText('naTvgbProjectRoot',   status.project_root);
        na__tvgb__setText('naTvgbTargetFolder',  status.target_folder);

        var briefEl = document.getElementById('naTvgbProjectBrief');
        if (briefEl) {
            if (status.linked && status.project_brief) {
                briefEl.textContent = status.project_brief;
            } else if (status.linked) {
                briefEl.textContent = 'Linked. Exports write into the design phase folder selected below.';
            } else if (!status.portal_found) {
                briefEl.textContent = 'The na-project-portal folder was not found on this machine. Set the portal root below, then link a project.';
            } else {
                briefEl.textContent = 'Link this model to a Noble Architecture project to export straight into the project portal and push to Cloudflare R2.';
            }
        }

        var portalInput = document.getElementById('naTvgbPortalInput');
        if (portalInput && !portalInput.value && status.portal_root) {
            portalInput.value = status.portal_root;
        }
    }

    function na__tvgb__renderPhaseSelect() {
        var select = document.getElementById('naTvgbNewPhaseSelect');
        if (!select) { return; }

        var previous = select.value;
        select.innerHTML = naTvgbProject.phases.map(function(phase) {
            var label = phase.label + (phase.supports_schemes ? ' — next: ' + phase.next_folder_name : ' — ' + phase.next_folder_name);
            return '<option value="' + na__tvgb__escHtml(phase.phase_id) + '">' + na__tvgb__escHtml(label) + '</option>';
        }).join('');

        if (previous) { select.value = previous; }
    }

    function na__tvgb__renderSchemeList() {
        var list = document.getElementById('naTvgbSchemeList');
        if (!list) { return; }

        if (naTvgbProject.folders.length === 0) {
            list.innerHTML = '<div class="naTvgb__Note naTvgb__Note--empty">'
                + (naTvgbProject.linked
                    ? 'No design phase folders yet. Create one below.'
                    : 'Link a project to see its design phase folders.')
                + '</div>';
            return;
        }

        list.innerHTML = naTvgbProject.folders.map(function(folder) {
            var selected = folder.folder_name === naTvgbProject.selectedFolder;
            var meta     = folder.glb_count + ' GLB' + (folder.glb_count === 1 ? '' : 's');
            if (folder.last_written) { meta += ' · last written ' + folder.last_written; }

            var tag = '';
            if (!folder.recognised) {
                tag = '<span class="naTvgb__SchemeRow__Tag naTvgb__SchemeRow__Tag--unrecognised">Unknown</span>';
            } else if (folder.is_alias) {
                tag = '<span class="naTvgb__SchemeRow__Tag naTvgb__SchemeRow__Tag--alias">Legacy name</span>';
            } else if (folder.glb_count === 0) {
                tag = '<span class="naTvgb__SchemeRow__Tag naTvgb__SchemeRow__Tag--empty">Empty</span>';
            }

            return '<button type="button" class="naTvgb__SchemeRow' + (selected ? ' naTvgb__SchemeRow--selected' : '') + '"'
                + ' onclick="Na__Tvgb__SelectScheme(\'' + na__tvgb__escAttr(folder.folder_name) + '\')">'
                + '<span class="naTvgb__SchemeRow__Radio"></span>'
                + '<span class="naTvgb__SchemeRow__Body">'
                + '<span class="naTvgb__SchemeRow__Name">' + na__tvgb__escHtml(folder.folder_name) + '</span>'
                + '<span class="naTvgb__SchemeRow__Meta">' + na__tvgb__escHtml(folder.phase_label + ' · ' + meta) + '</span>'
                + '</span>'
                + tag
                + '</button>';
        }).join('');
    }

    function na__tvgb__escAttr(raw) {
        return String(raw).replace(/\\/g, '\\\\').replace(/'/g, "\\'");
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Bootstrap - Ready Signal and Window API Surface
    // -----------------------------------------------------------------------------

    document.addEventListener('DOMContentLoaded', function() {
        Na__Tvgb__ToggleMaterialDependency();   // <-- Sync the dependent row to its checkbox
        na__tvgb__applyButtonLockState();       // <-- Start locked until Ruby pushes real state

        // <-- Signal Ruby that the dialog DOM is ready so it can push initial state
        if (window.sketchup && window.sketchup.na_tvgb_dialog_ready) {
            window.sketchup.na_tvgb_dialog_ready();
        }
    });

    window.Na__Tvgb__ShowTab                  = Na__Tvgb__ShowTab;
    window.Na__Tvgb__RunExportAction          = Na__Tvgb__RunExportAction;
    window.Na__Tvgb__ToggleMaterialDependency = Na__Tvgb__ToggleMaterialDependency;
    window.Na__Tvgb__HandleLogoError          = Na__Tvgb__HandleLogoError;
    window.Na__Tvgb__ReceiveReport            = Na__Tvgb__ReceiveReport;
    window.Na__Tvgb__ReceiveModelStatus       = Na__Tvgb__ReceiveModelStatus;

    window.Na__Tvgb__OpenProjectLinkModal     = Na__Tvgb__OpenProjectLinkModal;
    window.Na__Tvgb__DismissProjectModal      = Na__Tvgb__DismissProjectModal;
    window.Na__Tvgb__SubmitProjectCode        = Na__Tvgb__SubmitProjectCode;
    window.Na__Tvgb__HandleCodeInput          = Na__Tvgb__HandleCodeInput;
    window.Na__Tvgb__HandleCodeKeydown        = Na__Tvgb__HandleCodeKeydown;
    window.Na__Tvgb__RunProjectAction         = Na__Tvgb__RunProjectAction;
    window.Na__Tvgb__SelectScheme             = Na__Tvgb__SelectScheme;
    window.Na__Tvgb__ConfirmUnlinkProject     = Na__Tvgb__ConfirmUnlinkProject;
    window.Na__Tvgb__CloseConfirmModal        = Na__Tvgb__CloseConfirmModal;
    window.Na__Tvgb__AcceptConfirmModal       = Na__Tvgb__AcceptConfirmModal;
    window.Na__Tvgb__ReceiveProjectStatus     = Na__Tvgb__ReceiveProjectStatus;
    window.Na__Tvgb__ReceiveProjectLinkResult = Na__Tvgb__ReceiveProjectLinkResult;

    // endregion -------------------------------------------------------------------


    // =============================================================================
    // END OF FILE
    // =============================================================================
})();
