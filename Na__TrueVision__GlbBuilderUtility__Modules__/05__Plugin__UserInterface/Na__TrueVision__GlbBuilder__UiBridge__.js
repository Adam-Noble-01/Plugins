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

        // A target folder that already holds GLBs is confirmed before anything is
        // written, and the user picks what happens to the files already there.
        if (needsProject && naTvgbProject.targetGlbCount > 0) {
            na__tvgb__showConfirm({
                title:           'This scheme already has models',
                text:            naTvgbProject.targetFolder + ' holds ' + naTvgbProject.targetGlbCount
                                 + ' GLB file(s). Archiving zips them into that folder’s 00__Archive first, '
                                 + 'which stays on this machine and is never uploaded. Overwriting replaces them '
                                 + 'with no copy kept.',
                detail:          naTvgbProject.targetFolder,
                structure:       true,
                affectedFolder:  naTvgbProject.targetFolder,
                acceptLabel:     'Archive, Then Export',
                acceptVariant:   'success',
                secondaryLabel:  'Overwrite Without Archiving',
                secondaryVariant:'danger',
                onSecondary:     function() { na__tvgb__sendExportAction(actionId, true); }
            }, function() {
                na__tvgb__sendExportAction(actionId, false);
            });
            return;
        }

        na__tvgb__sendExportAction(actionId, false);
    }

    // HELPER FUNCTION | Send An Export Action With The Current Option Set
    // ------------------------------------------------------------
    // `skipArchive` carries the user's choice from the overwrite modal through
    // to Ruby, which is the only place the old files are actually touched.
    // ------------------------------------------------------------
    function na__tvgb__sendExportAction(actionId, skipArchive) {
        var params = na__tvgb__collectExportParams();
        params.confirmedOverwrite = true;      // <-- The UI has already asked, where asking was needed
        params.skipArchive        = !!skipArchive;

        naTvgbState.isRunning = true;
        na__tvgb__applyButtonLockState();       // <-- Disables all cards while running
        na__tvgb__setStatus('Running: ' + actionId.split('_').join(' ') + '...', 'info');

        window.sketchup.na_tvgb_run_action(String(actionId), JSON.stringify(params));
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Export File Selection
    // -----------------------------------------------------------------------------
    //
    // Which GLBs this model writes. Every toggle is persisted into the model's
    // attribute dictionary by Ruby, so the choice survives the session and
    // travels with the .skp. Ruby re-pushes the model status, which repaints
    // the manifest, so the JS never has to track the state itself.
    //
    // -----------------------------------------------------------------------------

    // FUNCTION | Toggle One File
    // ------------------------------------------------------------
    function Na__Tvgb__ToggleFile(fileName, selected) {
        na__tvgb__sendSelection({ scope: 'files', fileNames: [String(fileName)], selected: !!selected });
    }

    // FUNCTION | Toggle Every File In One Group
    // ------------------------------------------------------------
    function Na__Tvgb__ToggleGroup(groupIndex, selected) {
        var group = naTvgbManifestGroups[groupIndex];
        if (!group) { return; }

        var names = (group.rows || []).map(function(row) { return String(row.name || ''); });
        na__tvgb__sendSelection({ scope: 'files', fileNames: names, selected: !!selected });
    }

    // FUNCTION | Enable Or Disable Everything At Once
    // ------------------------------------------------------------
    function Na__Tvgb__SetAllFilesSelected(selected) {
        na__tvgb__sendSelection({ scope: 'all', selected: !!selected });
    }

    function na__tvgb__sendSelection(payload) {
        if (naTvgbState.isRunning) {
            na__tvgb__setStatus('Wait for the current action to finish.', 'warning');
            return;
        }
        if (!window.sketchup || !window.sketchup.na_tvgb_run_action) {
            na__tvgb__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }

        window.sketchup.na_tvgb_run_action('set_file_selection', JSON.stringify(payload));
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

        naTvgbManifestGroups = Array.isArray(status.groups) ? status.groups : [];
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

        var totalFiles    = Number(status.total_file_count || 0);
        var selectedFiles = (status.selected_file_count === undefined)
            ? totalFiles
            : Number(status.selected_file_count);

        if (countEl) {
            countEl.textContent = totalFiles === 0 ? 'Nothing to export' : totalFiles + ' GLB files';
        }
        na__tvgb__renderSelectionCount(totalFiles, selectedFiles);

        var html = '';

        // Advisory notes first, in the order Ruby supplied them
        var notes = Array.isArray(status.notes) ? status.notes : [];
        for (var ni = 0; ni < notes.length; ni += 1) {
            html += na__tvgb__noteHtml(notes[ni]);
        }

        // Then the file groups
        var groups = Array.isArray(status.groups) ? status.groups : [];
        for (var gi = 0; gi < groups.length; gi += 1) {
            html += na__tvgb__groupHtml(groups[gi], gi);
        }

        bodyEl.innerHTML = html;
        na__tvgb__applyIndeterminateToggles(bodyEl);
    }

    // HELPER FUNCTION | Show How Much Of The Manifest Is Switched On
    // ------------------------------------------------------------
    function na__tvgb__renderSelectionCount(totalFiles, selectedFiles) {
        var el = document.getElementById('naTvgbSelectionCount');
        if (!el) { return; }

        if (totalFiles === 0) {
            el.textContent = '—';
            el.className   = 'naTvgb__SelectBar__Count';
            return;
        }

        var partial = selectedFiles < totalFiles;
        el.textContent = selectedFiles + ' of ' + totalFiles + ' selected';
        el.className   = 'naTvgb__SelectBar__Count' + (partial ? ' naTvgb__SelectBar__Count--partial' : '');

        na__tvgb__lockButton('naTvgbEnableAllBtn',  selectedFiles === totalFiles);
        na__tvgb__lockButton('naTvgbDisableAllBtn', selectedFiles === 0);
    }

    // HELPER FUNCTION | Apply The Tri-State To Mixed Group Toggles
    // ------------------------------------------------------------
    // `indeterminate` is a property, not an attribute, so it has to be set
    // after the markup is in the DOM.
    // ------------------------------------------------------------
    function na__tvgb__applyIndeterminateToggles(root) {
        var toggles = root.querySelectorAll('[data-na-indeterminate="1"]');
        for (var i = 0; i < toggles.length; i += 1) {
            toggles[i].indeterminate = true;
        }
    }

    function na__tvgb__noteHtml(note) {
        if (!note) { return ''; }

        var variant = na__tvgb__escHtml(note.variant || 'empty');
        var title   = note.title ? '<strong>' + na__tvgb__escHtml(note.title) + '</strong> ' : '';
        var text    = na__tvgb__escHtml(note.text || '');

        return '<div class="naTvgb__Note naTvgb__Note--' + variant + '">' + title + text + '</div>';
    }

    function na__tvgb__groupHtml(group, groupIndex) {
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

        // The group's own toggle: on when every file in it is on, and
        // indeterminate when only some are, so a mixed storey reads as mixed.
        var onCount = rows.filter(function(r) { return r.selected !== false; }).length;
        var allOn   = onCount === rows.length && rows.length > 0;
        var someOn  = onCount > 0 && onCount < rows.length;

        var icon  = group.icon ? na__tvgb__escHtml(group.icon) + ' ' : '';
        var count = group.count_label
            ? '<span class="naTvgb__StoreyBlock__Count">' + na__tvgb__escHtml(group.count_label) + '</span>'
            : '';

        return '<details class="naTvgb__StoreyBlock" open>'
            + '<summary class="naTvgb__StoreyBlock__Heading">'
            + '<input type="checkbox" class="naTvgb__StoreyBlock__Toggle"'
            + ' data-na-group-index="' + groupIndex + '"'
            + (allOn ? ' checked' : '')
            + (someOn ? ' data-na-indeterminate="1"' : '')
            + ' onclick="event.stopPropagation(); Na__Tvgb__ToggleGroup(' + groupIndex + ', this.checked);">'
            + '<span class="naTvgb__StoreyBlock__HeadingText">' + icon + na__tvgb__escHtml(group.label) + '</span>'
            + count
            + '</summary>'
            + rowsHtml
            + '</details>';
    }

    function na__tvgb__fileRowHtml(row) {
        if (!row) { return ''; }

        var name = String(row.name || '');
        var on   = row.selected !== false;          // <-- Absent means selected

        return '<div class="naTvgb__FileRow' + (on ? '' : ' naTvgb__FileRow--off') + '">'
            + '<input type="checkbox" class="naTvgb__FileRow__Toggle"' + (on ? ' checked' : '')
            + ' title="Export this file"'
            + ' onchange="Na__Tvgb__ToggleFile(\'' + na__tvgb__escAttr(name) + '\', this.checked);">'
            + '<span class="naTvgb__FileRow__Name">'  + na__tvgb__escHtml(name) + '</span>'
            + '<span class="naTvgb__SelectBar__Spacer"></span>'
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
        var running = naTvgbState.isRunning;
        var r2Fetch = document.getElementById('naTvgbR2Fetch');
        if (r2Fetch) { r2Fetch.disabled = running || !naTvgbProject.linked; }
        if (window.Na__Tvgb__LockR2) { window.Na__Tvgb__LockR2(running || !naTvgbProject.linked); }
                // <-- A run locks everything, on top of the capability rules

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

        // Danger Zone: driven by its own folder picker, not the scheme list
        var dangerFolder = na__tvgb__readValue('naTvgbDangerFolderSelect');
        na__tvgb__lockButton('naTvgbDeleteBtn', running || noProject || !dangerFolder);

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
        structure      : [],      // <-- folder tree rows for the structure panel
        portalFound    : false
    };

    var NA_TVGB_PROJECT_CODE_PATTERN = /^[A-Z]{2}[0-9]{2}$/;

    // Last manifest Ruby pushed, so a group toggle knows which files it owns
    var naTvgbManifestGroups = [];

    // Actions that create, copy or remove folders. Each has its own confirmation
    // function; the generic RunProjectAction path refuses them outright.
    var NA_TVGB_CONFIRMED_ACTIONS = ['create_scheme', 'duplicate_scheme', 'delete_scheme', 'purge_r2'];

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

    var naTvgbPendingConfirm   = null;   // <-- function run when the user accepts
    var naTvgbPendingSecondary = null;   // <-- function run for the modal's second choice

    var naTvgbConfirmTypeTarget = '';   // <-- when set, the user must type this exactly

    // FUNCTION | Ask The User To Confirm, Then Run The Supplied Action
    // ------------------------------------------------------------
    // options:
    //   title, text, detail        - the wording
    //   acceptLabel, danger        - the accept button
    //   structure                  - true to show the live project tree
    //   affectedFolder             - folder highlighted red in that tree
    //   typeToConfirm              - string the user must type out before accepting
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

        // Project structure, with the affected folder flagged
        var structWrap = document.getElementById('naTvgbConfirmStructureWrap');
        if (structWrap) {
            if (options.structure) {
                na__tvgb__renderTree('naTvgbConfirmStructure', naTvgbProject.structure, options.affectedFolder);
                structWrap.hidden = false;
            } else {
                structWrap.hidden = true;
            }
        }

        // Type-to-confirm
        naTvgbConfirmTypeTarget = options.typeToConfirm || '';
        var typeWrap  = document.getElementById('naTvgbConfirmTypeWrap');
        var typeInput = document.getElementById('naTvgbConfirmTypeInput');
        if (typeWrap) {
            typeWrap.hidden = !naTvgbConfirmTypeTarget;
            if (naTvgbConfirmTypeTarget) {
                na__tvgb__setText2('naTvgbConfirmTypePrompt', 'Type ' + naTvgbConfirmTypeTarget + ' to confirm:');
                if (typeInput) { typeInput.value = ''; }
            }
        }

        var acceptBtn = document.getElementById('naTvgbConfirmAccept');
        if (acceptBtn) {
            acceptBtn.textContent = options.acceptLabel || 'Continue';
            acceptBtn.className   = 'naTvgb__Btn ' + na__tvgb__btnVariant(options.acceptVariant, options.danger);
            acceptBtn.disabled    = !!naTvgbConfirmTypeTarget;   // <-- Unlocked once the name matches
        }

        // Optional second action, for a modal offering two real choices
        var secondaryBtn = document.getElementById('naTvgbConfirmSecondary');
        naTvgbPendingSecondary = options.onSecondary || null;
        if (secondaryBtn) {
            if (options.secondaryLabel && naTvgbPendingSecondary) {
                secondaryBtn.textContent = options.secondaryLabel;
                secondaryBtn.className   = 'naTvgb__Btn ' + na__tvgb__btnVariant(options.secondaryVariant, true);
                secondaryBtn.disabled    = !!naTvgbConfirmTypeTarget;
                secondaryBtn.hidden      = false;
            } else {
                secondaryBtn.hidden = true;
            }
        }

        naTvgbPendingConfirm = onAccept;
        modal.hidden = false;

        if (naTvgbConfirmTypeTarget && typeInput) { typeInput.focus(); }
    }

    function na__tvgb__btnVariant(variant, danger) {
        if (variant === 'success') { return 'naTvgb__Btn--success'; }
        if (variant === 'primary') { return 'naTvgb__Btn--primary'; }
        if (variant === 'danger')  { return 'naTvgb__Btn--danger';  }
        return danger === false ? 'naTvgb__Btn--primary' : 'naTvgb__Btn--danger';
    }

    // FUNCTION | Run The Modal's Second Action
    // ------------------------------------------------------------
    function Na__Tvgb__AcceptConfirmSecondary() {
        if (naTvgbConfirmTypeTarget) {
            var input = document.getElementById('naTvgbConfirmTypeInput');
            if (!input || !na__tvgb__confirmTypingMatches(input.value)) { return; }
        }

        var action = naTvgbPendingSecondary;
        na__tvgb__hideElement('naTvgbConfirmModal');
        naTvgbPendingConfirm    = null;
        naTvgbPendingSecondary  = null;
        naTvgbConfirmTypeTarget = '';

        if (typeof action === 'function') { action(); }
    }

    // FUNCTION | Unlock The Accept Button Only On An Exact Match
    // ------------------------------------------------------------
    function Na__Tvgb__HandleConfirmTyping() {
        var input     = document.getElementById('naTvgbConfirmTypeInput');
        var accept    = document.getElementById('naTvgbConfirmAccept');
        var secondary = document.getElementById('naTvgbConfirmSecondary');
        if (!input || !accept || !naTvgbConfirmTypeTarget) { return; }

        var matched = na__tvgb__confirmTypingMatches(input.value);
        accept.disabled = !matched;
        if (secondary && !secondary.hidden) { secondary.disabled = !matched; }
    }

    // HELPER FUNCTION | Compare The Typed Confirmation
    // ------------------------------------------------------------
    // Case-insensitive: the target is usually a project code, and being made to
    // match the capitals of RB05 adds nothing to the deliberation.
    // ------------------------------------------------------------
    function na__tvgb__confirmTypingMatches(value) {
        if (!naTvgbConfirmTypeTarget) { return true; }

        return String(value || '').trim().toUpperCase() === naTvgbConfirmTypeTarget.toUpperCase();
    }

    function Na__Tvgb__HandleConfirmTypingKeydown(event) {
        if (!event) { return; }
        if (event.key === 'Escape') { Na__Tvgb__CloseConfirmModal(); return; }

        var accept = document.getElementById('naTvgbConfirmAccept');
        if (event.key === 'Enter' && accept && !accept.disabled) { Na__Tvgb__AcceptConfirmModal(); }
    }

    function Na__Tvgb__CloseConfirmModal() {
        na__tvgb__hideElement('naTvgbConfirmModal');
        naTvgbPendingConfirm    = null;
        naTvgbPendingSecondary  = null;
        naTvgbConfirmTypeTarget = '';
    }

    function Na__Tvgb__AcceptConfirmModal() {
        // Belt and braces: never act on a type-to-confirm that does not match,
        // whatever state the button happens to be in.
        if (naTvgbConfirmTypeTarget) {
            var input = document.getElementById('naTvgbConfirmTypeInput');
            if (!input || !na__tvgb__confirmTypingMatches(input.value)) { return; }
        }

        var action = naTvgbPendingConfirm;
        na__tvgb__hideElement('naTvgbConfirmModal');
        naTvgbPendingConfirm    = null;
        naTvgbPendingSecondary  = null;
        naTvgbConfirmTypeTarget = '';

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

        // Anything that writes or removes folders must go through its own
        // confirmation function. This generic path must never reach them, so a
        // future wiring mistake cannot resurrect the unguarded Duplicate.
        if (NA_TVGB_CONFIRMED_ACTIONS.indexOf(actionId) !== -1) {
            na__tvgb__setStatus('That action needs confirming - use its own button.', 'warning');
            return;
        }

        na__tvgb__dispatch(actionId, {
            phaseId:        na__tvgb__selectedPhaseId(),
            selectedFolder: naTvgbProject.selectedFolder,
            portalRoot:     na__tvgb__readValue('naTvgbPortalInput')
        });
    }

    // FUNCTION | Highlight A Scheme Folder And Make It The Export Target
    // ------------------------------------------------------------
    function Na__Tvgb__SelectScheme(folderName) {
        naTvgbProject.selectedFolder = String(folderName || '');
        na__tvgb__renderSchemeList();

        na__tvgb__dispatch('set_target_folder', { targetFolder: naTvgbProject.selectedFolder });
    }

    // FUNCTION | Confirm Before Creating A New Design Phase Folder
    // ------------------------------------------------------------
    // Creating a folder is not destructive, but it does add a model group that
    // the next push publishes to R2, so it is worth a look before it happens.
    // ------------------------------------------------------------
    function Na__Tvgb__ConfirmCreateScheme() {
        if (!naTvgbProject.linked) {
            na__tvgb__setStatus('Link this model to a project first.', 'warning');
            return;
        }

        var phase = na__tvgb__selectedPhase();
        if (!phase) {
            na__tvgb__setStatus('Choose which design phase to create.', 'warning');
            return;
        }

        na__tvgb__showConfirm({
            title:         'Create ' + phase.next_folder_name + '?',
            text:          'A new, empty ' + phase.label + ' folder will be created in the project portal and '
                           + 'become this model’s export target. It is published to TrueVision and Cloudflare R2 '
                           + 'on the next push.',
            detail:        phase.next_folder_name,
            structure:     true,
            acceptLabel:   'Create Folder',
            danger:        false
        }, function() {
            na__tvgb__dispatch('create_scheme', { phaseId: phase.phase_id });
        });
    }

    // FUNCTION | Confirm Before Duplicating A Scheme
    // ------------------------------------------------------------
    // This one copies every GLB in the source folder. Done by accident it
    // silently doubles the project, so it names the file count and the
    // destination, and shows the whole structure.
    // ------------------------------------------------------------
    function Na__Tvgb__ConfirmDuplicateScheme() {
        if (!naTvgbProject.linked) {
            na__tvgb__setStatus('Link this model to a project first.', 'warning');
            return;
        }

        var source = na__tvgb__folderByName(naTvgbProject.selectedFolder);
        if (!source) {
            na__tvgb__setStatus('Select the scheme you want to duplicate first.', 'warning');
            return;
        }

        var phase = na__tvgb__phaseById(source.phase_id);
        var into  = phase ? phase.next_folder_name : '(the next scheme)';

        na__tvgb__showConfirm({
            title:          'Duplicate this scheme?',
            text:           'This copies all ' + source.glb_count + ' GLB file(s) from '
                            + source.folder_name + ' into a new folder, ' + into + '. '
                            + 'That becomes a second model group in TrueVision, and the next push uploads every '
                            + 'copied file to Cloudflare R2.',
            detail:         source.folder_name + '  →  ' + into,
            structure:      true,
            affectedFolder: source.folder_name,
            acceptLabel:    'Duplicate ' + source.glb_count + ' Files'
        }, function() {
            na__tvgb__dispatch('duplicate_scheme', { selectedFolder: source.folder_name });
        });
    }

    // FUNCTION | Confirm Before Deleting A Design Phase Folder
    // ------------------------------------------------------------
    // The folder name must be typed out in full. Ruby re-checks the typed value
    // before it removes anything.
    // ------------------------------------------------------------
    function Na__Tvgb__ConfirmDeleteScheme() {
        if (!naTvgbProject.linked) {
            na__tvgb__setStatus('Link this model to a project first.', 'warning');
            return;
        }

        var folderName = na__tvgb__readValue('naTvgbDangerFolderSelect');
        var folder     = na__tvgb__folderByName(folderName);
        if (!folder) {
            na__tvgb__setStatus('Choose the folder you want to delete.', 'warning');
            return;
        }

        var permanentEl = document.getElementById('naTvgbDangerPermanent');
        var permanent   = !!(permanentEl && permanentEl.checked);

        var text = permanent
            ? 'This permanently deletes ' + folder.folder_name + ' and all ' + folder.glb_count
              + ' GLB file(s) in it. There is no undo.'
            : 'This moves ' + folder.folder_name + ' and its ' + folder.glb_count
              + ' GLB file(s) into 00__Archive. The scheme disappears from TrueVision, and the files stay '
              + 'recoverable on disk.';

        na__tvgb__showConfirm({
            title:          permanent ? 'Permanently delete this folder?' : 'Delete this folder?',
            text:           text + ' Files already pushed to Cloudflare R2 are NOT removed by this.',
            detail:         folder.folder_name,
            structure:      true,
            affectedFolder: folder.folder_name,
            typeToConfirm:  naTvgbProject.code,
            acceptLabel:    permanent ? 'Delete Permanently' : 'Delete Folder'
        }, function() {
            na__tvgb__dispatch('delete_scheme', {
                targetFolder:      folder.folder_name,
                typedConfirmation: naTvgbProject.code,
                permanent:         permanent
            });
        });
    }


    // FUNCTION | Keep The Scheme List In Step With The Danger Zone Picker
    // ------------------------------------------------------------
    function Na__Tvgb__HandleDangerFolderChange() {
        na__tvgb__applyButtonLockState();
    }

    function na__tvgb__folderByName(name) {
        for (var i = 0; i < naTvgbProject.folders.length; i += 1) {
            if (naTvgbProject.folders[i].folder_name === name) { return naTvgbProject.folders[i]; }
        }
        return null;
    }

    function na__tvgb__phaseById(phaseId) {
        for (var i = 0; i < naTvgbProject.phases.length; i += 1) {
            if (naTvgbProject.phases[i].phase_id === phaseId) { return naTvgbProject.phases[i]; }
        }
        return null;
    }

    function na__tvgb__selectedPhase() {
        return na__tvgb__phaseById(na__tvgb__selectedPhaseId());
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
        if (actionId === 'fetch_r2' || actionId === 'push_to_cloud' || actionId === 'export_and_sync' || actionId === 'link_project' || actionId === 'unlink_project') {
            if (window.Na__Tvgb__ReceiveR2) { window.Na__Tvgb__ReceiveR2({success: false, message: 'Refresh R2 after this operation.'}); }
        }
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
        naTvgbProject.phases         = Array.isArray(status.phases)    ? status.phases    : [];
        naTvgbProject.folders        = Array.isArray(status.folders)   ? status.folders   : [];
        naTvgbProject.structure      = Array.isArray(status.structure) ? status.structure : [];
        naTvgbProject.portalFound    = !!status.portal_found;

        if (!naTvgbProject.selectedFolder || !na__tvgb__folderExists(naTvgbProject.selectedFolder)) {
            naTvgbProject.selectedFolder = naTvgbProject.targetFolder;
        }


        na__tvgb__renderProjectCard(status);
        na__tvgb__renderPhaseSelect();
        na__tvgb__renderSchemeList();
        na__tvgb__renderTree('naTvgbStructureTree', naTvgbProject.structure, null);
        na__tvgb__renderDangerFolderSelect();
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

    // FUNCTION | Fill The Danger Zone's Own Folder Picker
    // ------------------------------------------------------------
    // The Danger Zone stands on its own: it picks its own folder rather than
    // borrowing whatever happens to be highlighted in the scheme list above,
    // so nothing destructive depends on a selection made elsewhere.
    // ------------------------------------------------------------
    function na__tvgb__renderDangerFolderSelect() {
        var select = document.getElementById('naTvgbDangerFolderSelect');
        if (!select) { return; }

        var previous = select.value;

        if (naTvgbProject.folders.length === 0) {
            select.innerHTML = '<option value="">No design phase folders</option>';
            return;
        }

        select.innerHTML = naTvgbProject.folders.map(function(folder) {
            var label = folder.folder_name + '  (' + folder.glb_count + ' GLB'
                      + (folder.glb_count === 1 ? '' : 's') + ')';
            return '<option value="' + na__tvgb__escHtml(folder.folder_name) + '">'
                 + na__tvgb__escHtml(label) + '</option>';
        }).join('');

        // Keep the previous choice when it still exists, otherwise fall back to
        // the model's export target rather than silently aiming at folder one.
        if (previous && na__tvgb__folderByName(previous)) {
            select.value = previous;
        } else if (naTvgbProject.targetFolder && na__tvgb__folderByName(naTvgbProject.targetFolder)) {
            select.value = naTvgbProject.targetFolder;
        }
    }


    // FUNCTION | Render The Project Folder Tree
    // ------------------------------------------------------------
    // `affectedFolder` paints one row red: the folder the pending action is
    // about to change. The model's export target is painted blue.
    // ------------------------------------------------------------
    function na__tvgb__renderTree(elementId, rows, affectedFolder) {
        var el = document.getElementById(elementId);
        if (!el) { return; }

        if (!Array.isArray(rows) || rows.length === 0) {
            el.innerHTML = '<div class="naTvgb__Tree__Row"><span class="naTvgb__Tree__Meta">'
                + (naTvgbProject.linked ? 'No folders found on disk.' : 'Link a project to read its structure.')
                + '</span></div>';
            return;
        }

        el.innerHTML = rows.map(function(row, index) {
            // An explicit affected folder overrides whatever marker Ruby sent
            var marker = row.marker || '';
            if (affectedFolder && row.label === affectedFolder) { marker = 'affected'; }
            else if (affectedFolder && marker === 'affected')   { marker = ''; }

            var isLast  = na__tvgb__isLastAtDepth(rows, index);
            var indent  = na__tvgb__treeIndent(row.depth, isLast);
            var tag     = '';
            if (marker === 'target')   { tag = '<span class="naTvgb__Tree__Tag naTvgb__Tree__Tag--target">Target</span>'; }
            if (marker === 'affected') { tag = '<span class="naTvgb__Tree__Tag naTvgb__Tree__Tag--affected">Affected</span>'; }

            var cls = 'naTvgb__Tree__Row naTvgb__Tree__Row--' + na__tvgb__escHtml(row.kind || 'phase');
            if (marker) { cls += ' naTvgb__Tree__Row--' + marker; }

            return '<div class="' + cls + '">'
                + '<span class="naTvgb__Tree__Label">' + indent + na__tvgb__escHtml(row.label || '') + '</span>'
                + (row.meta ? '<span class="naTvgb__Tree__Meta">' + na__tvgb__escHtml(row.meta) + '</span>' : '')
                + tag
                + '</div>';
        }).join('');
    }

    function na__tvgb__isLastAtDepth(rows, index) {
        var depth = rows[index].depth;
        for (var i = index + 1; i < rows.length; i += 1) {
            if (rows[i].depth < depth)  { return true; }
            if (rows[i].depth === depth) { return false; }
        }
        return true;
    }

    function na__tvgb__treeIndent(depth, isLast) {
        var d = Number(depth || 0);
        if (d === 0) { return ''; }

        return new Array(d).join('  ') + (isLast ? '└─ ' : '├─ ');
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
    // Small public surface for the cloud-inventory module, which is its own
    // IIFE at the end of this file and cannot see these private helpers.
    window.Na__Tvgb__Confirm     = na__tvgb__showConfirm;
    window.Na__Tvgb__SetStatus   = na__tvgb__setStatus;
    window.Na__Tvgb__ProjectCode = function () { return naTvgbProject.code; };

    window.Na__Tvgb__ToggleFile               = Na__Tvgb__ToggleFile;
    window.Na__Tvgb__ToggleGroup              = Na__Tvgb__ToggleGroup;
    window.Na__Tvgb__SetAllFilesSelected      = Na__Tvgb__SetAllFilesSelected;

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
    window.Na__Tvgb__AcceptConfirmSecondary   = Na__Tvgb__AcceptConfirmSecondary;
    window.Na__Tvgb__ConfirmCreateScheme      = Na__Tvgb__ConfirmCreateScheme;
    window.Na__Tvgb__ConfirmDuplicateScheme   = Na__Tvgb__ConfirmDuplicateScheme;
    window.Na__Tvgb__ConfirmDeleteScheme      = Na__Tvgb__ConfirmDeleteScheme;
    window.Na__Tvgb__HandleDangerFolderChange = Na__Tvgb__HandleDangerFolderChange;
    window.Na__Tvgb__HandleConfirmTyping      = Na__Tvgb__HandleConfirmTyping;
    window.Na__Tvgb__HandleConfirmTypingKeydown = Na__Tvgb__HandleConfirmTypingKeydown;
    window.Na__Tvgb__ReceiveProjectStatus     = Na__Tvgb__ReceiveProjectStatus;
    window.Na__Tvgb__ReceiveProjectLinkResult = Na__Tvgb__ReceiveProjectLinkResult;

    // endregion -------------------------------------------------------------------


    // =============================================================================
    // END OF FILE
    // =============================================================================
})();

// Cloud inventory uses textContent so remote object names cannot inject markup.
(function () {
    var inventory = null;
    window.Na__Tvgb__LockR2 = function (locked) {
        var folder = document.getElementById('naTvgbR2Folders').value;
        document.getElementById('naTvgbR2Folders').disabled = locked;
        document.getElementById('naTvgbR2Purge').disabled = locked || !inventory || !inventory.folders[folder] || !inventory.folders[folder].length;
    };
    window.Na__Tvgb__ReceiveR2 = function (report) {
        inventory = report.success && report.folders ? report : null;
        var select = document.getElementById('naTvgbR2Folders');
        select.textContent = '';
        if (inventory) {
            Object.keys(inventory.folders).sort().forEach(function (folder) {
                var option = document.createElement('option');
                option.value = folder;
                option.textContent = folder + ' (' + inventory.folders[folder].length + ' GLBs)';
                select.appendChild(option);
            });
            window.Na__Tvgb__ReviewR2();
        } else {
            document.getElementById('naTvgbR2Report').textContent = report.message +
                (report.errors ? '\n' + report.errors.join('\n') : '') + (report.log_path ? '\nReport: ' + report.log_path : '') + '\nFetch R2 again before another purge.';
            document.getElementById('naTvgbR2Purge').disabled = true;
        }
    };
    window.Na__Tvgb__ReviewR2 = function () {
        var folder = document.getElementById('naTvgbR2Folders').value;
        var objects = inventory && inventory.folders[folder];
        document.getElementById('naTvgbR2Purge').disabled = !objects || !objects.length;
        document.getElementById('naTvgbR2Report').textContent = objects ?
            'Bucket: ' + inventory.bucket + '\nPrefix: ' + inventory.prefix + folder + '/\n' +
            objects.length + ' GLBs · ' + objects.reduce(function (sum, obj) { return sum + obj.size; }, 0) + ' bytes\n\n' +
            objects.map(function (obj) { return obj.key + ' (' + obj.size + ' bytes)'; }).join('\n') : 'No design phase GLBs found in R2.';
    };
    // FUNCTION | Confirm Before Purging One Folder From R2
    // ------------------------------------------------------------
    // Uses the dialog's own confirmation modal, and asks for the project code
    // rather than the folder name: the folder is chosen from a list and named
    // in the modal, so re-typing forty characters added nothing but keystrokes.
    // ------------------------------------------------------------
    window.Na__Tvgb__ConfirmPurgeR2Folder = function () {
        var folder  = document.getElementById('naTvgbR2Folders').value;
        var objects = inventory && inventory.folders[folder];

        if (!inventory || !objects || !objects.length) {
            window.Na__Tvgb__SetStatus('Fetch R2 and pick a folder that actually holds GLBs.', 'warning');
            return;
        }

        var projectCode = window.Na__Tvgb__ProjectCode();
        var bytes       = objects.reduce(function (sum, obj) { return sum + obj.size; }, 0);

        window.Na__Tvgb__Confirm({
            title:         'Purge this folder from Cloudflare R2?',
            text:          'This permanently deletes the ' + objects.length + ' GLB file(s) R2 holds for '
                           + folder + ' (' + na__tvgb__formatBytes(bytes) + '). There is no undo. Local files '
                           + 'and every other scheme are untouched, so a push afterwards re-uploads whatever '
                           + 'is still on disk.',
            detail:        inventory.bucket + '/' + inventory.prefix + folder + '/',
            typeToConfirm: projectCode,
            acceptLabel:   'Purge ' + objects.length + ' Files'
        }, function () {
            document.getElementById('naTvgbR2Purge').disabled = true;
            window.sketchup.na_tvgb_run_action('purge_r2_folder', JSON.stringify({
                cloudFolder:       folder,
                typedConfirmation: projectCode
            }));
        });
    };

    function na__tvgb__formatBytes(bytes) {
        var mb = Number(bytes || 0) / 1048576;
        if (mb >= 1) { return mb.toFixed(1) + ' MB'; }

        return Math.max(1, Math.round(Number(bytes || 0) / 1024)) + ' KB';
    }
}());
