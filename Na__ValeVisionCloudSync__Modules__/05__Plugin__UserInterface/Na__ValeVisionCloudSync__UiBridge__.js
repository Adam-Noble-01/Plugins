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
    // 06-Oct-2026 - Version 1.2.0
    // - Library Project and Server rows (Export tab); Project Library group (Settings tab)
    //   with Save Library Project / Use Folder Name; SKIP badge for skipped steps.
    //
    // 30-Oct-2026 - Version 1.3.0
    // - The Sync Aura tab: AURA sign-in (the password field is cleared the moment it is
    //   handed to Ruby), the AURA status rows, its two cards (locked until signed in, never
    //   by the ValeVision 3D first-sync lock) and its own report block.
    //
    // =============================================================================


    // -----------------------------------------------------------------------------
    // REGION | Module State
    // -----------------------------------------------------------------------------

    var naVvcsState = {
        isRunning         : false,   // <-- true while a sync action is in progress
        activeTabId       : 'export',// <-- tracks which tab is visible
        firstSyncComplete : false,   // <-- true once a full sync has succeeded for this model (unlocks Update cards)
        auraSignedIn      : false    // <-- true while this PC holds an AURA session (unlocks the Sync Aura cards)
    };

    var NA_VVCS_REQUIRES_SYNC_SELECTOR = '.naVvcs__ActionCard[data-na-requires-sync="true"]'; // <-- The three Update cards
    var NA_VVCS_REQUIRES_AURA_SELECTOR = '.naVvcs__ActionCard[data-na-requires-aura="true"]'; // <-- The two Sync Aura cards

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
        var isAura = actionId.indexOf('aura_') === 0;
        // <-- Update actions are locked until a full Sync Project has succeeded once
        if (!isAura && actionId !== 'sync_project' && !naVvcsState.firstSyncComplete) {
            na__vvcs__setStatus('Run a full Sync Project To ValeVision 3D first.', 'warning');
            return;
        }
        if (isAura && !naVvcsState.auraSignedIn) {
            na__vvcs__setStatus('Sign in to AURA first (top of the Sync Aura tab).', 'warning');
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

    function Na__Vvcs__SaveLibraryId() {
        if (!window.sketchup || !window.sketchup.na_vvcs_save_library_id) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }
        var input = document.getElementById('naVvcsLibraryIdInput');
        var value = input ? input.value.trim() : '';
        if (!value) {
            na__vvcs__setStatus('Enter a library project, e.g. 64135__Washington.', 'warning');
            return;
        }
        window.sketchup.na_vvcs_save_library_id(value);
    }

    function Na__Vvcs__ClearLibraryId() {
        if (!window.sketchup || !window.sketchup.na_vvcs_clear_library_id) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }
        var input = document.getElementById('naVvcsLibraryIdInput');
        if (input) { input.value = ''; }
        window.sketchup.na_vvcs_clear_library_id();
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | SketchUp Bridge — AURA Sign-In
    // -----------------------------------------------------------------------------

    // FUNCTION | Sign In (the password leaves the field the moment it is handed over)
    // ------------------------------------------------------------
    function Na__Vvcs__AuraSignIn() {
        if (!window.sketchup || !window.sketchup.na_vvcs_aura_signin) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }
        var emailEl    = document.getElementById('naVvcsAuraEmail');
        var passwordEl = document.getElementById('naVvcsAuraPassword');
        var email      = emailEl ? emailEl.value.trim() : '';
        var password   = passwordEl ? passwordEl.value : '';
        if (!email || !password) {
            na__vvcs__setStatus('Enter your email address and password.', 'warning');
            return;
        }
        if (passwordEl) { passwordEl.value = ''; }
        na__vvcs__setStatus('Signing in to AURA...', 'info');
        window.sketchup.na_vvcs_aura_signin(email, password);
        password = '';
    }

    function Na__Vvcs__AuraSignOut() {
        if (!window.sketchup || !window.sketchup.na_vvcs_aura_signout) {
            na__vvcs__setStatus('SketchUp bridge unavailable.', 'error');
            return;
        }
        na__vvcs__setStatus('Signing out of AURA...', 'info');
        window.sketchup.na_vvcs_aura_signout();
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
        naVvcsState.auraSignedIn      = !!(pathData.aura && pathData.aura.signed_in);
        na__vvcs__applyButtonLockState();
        na__vvcs__renderAuraStatus(pathData.aura || null, pathData.library || null);

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

        na__vvcs__renderLibraryStatus(pathData.library || null);
    }

    // FUNCTION | Library Project + Server Rows, and the Settings Library Group
    // ------------------------------------------------------------
    function na__vvcs__renderLibraryStatus(library) {
        var projectEl = document.getElementById('naVvcsLibraryProject');
        var serverEl  = document.getElementById('naVvcsServerMode');
        var pathEl    = document.getElementById('naVvcsLibraryPath');
        var inputEl   = document.getElementById('naVvcsLibraryIdInput');
        var base      = 'naVvcs__ProjectStatus__Value';

        if (!library) {
            if (projectEl) { projectEl.textContent = '—'; projectEl.className = base; }
            if (serverEl)  { serverEl.textContent  = '—'; }
            if (pathEl)    { pathEl.textContent    = '—'; }
            return;
        }

        if (projectEl) {
            if (library.error) {
                projectEl.textContent = library.error;
                projectEl.className   = base + ' ' + base + '--error';
            } else if (!library.exists) {
                projectEl.textContent = 'NEW: ' + library.rel + ' (created by the first sync, after you confirm)';
                projectEl.className   = base + ' ' + base + '--new';
            } else {
                projectEl.textContent = library.rel + (library.source === 'override' ? ' (set in Settings)' : '');
                projectEl.className   = base + (library.source === 'override' ? ' ' + base + '--override' : '');
            }
        }
        if (serverEl) {
            serverEl.textContent = library.push
                ? 'Push to app.valegardenhouses.com (this project only)'
                : 'Local only: push_to_server is off in the plugin AppConfig';
        }
        if (pathEl) {
            pathEl.textContent = library.library_path || '—';
        }
        if (inputEl) {
            inputEl.value       = library.source === 'override' ? (library.library_id || '') : '';
            inputEl.placeholder = library.source === 'derived' && library.library_id ? library.library_id : '64135__Washington';
        }
    }

    // FUNCTION | The Sync Aura Tab: Sign-In Card and Status Rows
    // ------------------------------------------------------------
    function na__vvcs__renderAuraStatus(aura, library) {
        var signedInEl  = document.getElementById('naVvcsAuraSignedIn');
        var signedOutEl = document.getElementById('naVvcsAuraSignedOut');
        var userEl      = document.getElementById('naVvcsAuraUser');
        var libraryEl   = document.getElementById('naVvcsAuraLibraryProject');
        var proxiesEl   = document.getElementById('naVvcsAuraProxies');
        var lastEl      = document.getElementById('naVvcsAuraLastSync');
        var base        = 'naVvcs__ProjectStatus__Value';
        var signedIn    = !!(aura && aura.signed_in);

        if (signedInEl)  { signedInEl.style.display  = signedIn ? '' : 'none'; }
        if (signedOutEl) { signedOutEl.style.display = signedIn ? 'none' : ''; }
        if (userEl) {
            userEl.textContent = signedIn
                ? (aura.user_name || aura.email || 'Signed in') + (aura.user_level ? ' (' + aura.user_level + ')' : '')
                : '—';
        }
        if (libraryEl) {
            if (!library)              { libraryEl.textContent = '—'; libraryEl.className = base; }
            else if (library.error)    { libraryEl.textContent = library.error; libraryEl.className = base + ' ' + base + '--error'; }
            else if (!library.exists)  { libraryEl.textContent = library.rel + ': not in the Project Library yet (sync it to ValeVision 3D first)'; libraryEl.className = base + ' ' + base + '--error'; }
            else                       { libraryEl.textContent = library.rel + ' (switch it on for AURA in the Gallery\'s Project Editor)'; libraryEl.className = base; }
        }
        if (proxiesEl) {
            if (!aura) {
                proxiesEl.textContent = '—';
            } else {
                var text = String(aura.proxies || 0) + ' in the model, ' + String(aura.synced || 0) + ' linked to AURA';
                if (aura.proxy_tag) { text += ', on ' + aura.proxy_tag; }
                if (!aura.assets_plugin) { text += '. Na PainterlyNPR Assets is not loaded: AURA\'s new assets cannot be placed'; }
                proxiesEl.textContent = text;
            }
        }
        if (lastEl) {
            lastEl.textContent = aura && aura.last_sync
                ? aura.last_sync + (aura.base_project ? ' (' + aura.base_project + ')' : '')
                : 'Never';
        }
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Report Rendering
    // -----------------------------------------------------------------------------

    function na__vvcs__renderReport(report) {
        var scope     = String(report.scope || report.action_id || '');
        var prefix    = scope.indexOf('aura_') === 0 ? 'naVvcsAuraReport' : 'naVvcsReport';   // <-- Each tab shows its own last report
        var reportEl  = document.getElementById(prefix);
        var stepsEl   = document.getElementById(prefix + 'Steps');
        var summaryEl = document.getElementById(prefix + 'Summary');

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

        if (status === 'skip' || status === 'skipped') {
            cls = 'skip'; label = 'SKIP';                                   // <-- Checked first: a skipped step still carries success
        } else if (success === true || status === 'ok' || status === 'success') {
            cls = 'ok'; label = 'OK';
        } else if (success === false || status === 'error' || status === 'fail') {
            cls = 'error'; label = 'ERR';
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

        var lockAura  = !naVvcsState.auraSignedIn;
        var auraCards = document.querySelectorAll(NA_VVCS_REQUIRES_AURA_SELECTOR);
        for (var ai = 0; ai < auraCards.length; ai += 1) {
            auraCards[ai].disabled = lockAura;
            auraCards[ai].title    = lockAura ? 'Sign in to AURA first.' : '';
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
    window.Na__Vvcs__SaveLibraryId      = Na__Vvcs__SaveLibraryId;
    window.Na__Vvcs__ClearLibraryId     = Na__Vvcs__ClearLibraryId;
    window.Na__Vvcs__AuraSignIn         = Na__Vvcs__AuraSignIn;
    window.Na__Vvcs__AuraSignOut        = Na__Vvcs__AuraSignOut;
    window.Na__Vvcs__ReceiveReport      = Na__Vvcs__ReceiveReport;
    window.Na__Vvcs__ReceivePathStatus  = Na__Vvcs__ReceivePathStatus;

    // endregion -------------------------------------------------------------------


    // =============================================================================
    // END OF FILE
    // =============================================================================
})();
