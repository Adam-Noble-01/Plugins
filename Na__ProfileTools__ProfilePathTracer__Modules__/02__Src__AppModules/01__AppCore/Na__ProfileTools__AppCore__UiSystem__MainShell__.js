// =============================================================================
// NA PROFILE TOOLS - APP CORE - UI SYSTEM - MAIN SHELL
// =============================================================================
//
// FILE       : Na__ProfileTools__AppCore__UiSystem__MainShell__.js
// NAMESPACE  : window.Na__ProfileTools__MainShell
// PURPOSE    : Dialog-level initialisation and global UI helpers.
//              Runs after DOMContentLoaded — sets up the status bar and wires
//              the brand header (logo error-hide).
//
// =============================================================================

(function () {
    'use strict';

    var Na__ProfileTools__MainShell = {};

    // -------------------------------------------------------------------------
    // REGION | Brand Header Init
    // -------------------------------------------------------------------------

    function Na__Shell__InitBrandHeader() {
        var logo = document.querySelector('.na-brand-header__logo');
        if (!logo) return;
        logo.onerror = function () {
            this.style.display = 'none';
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Status Bar Init
    // -------------------------------------------------------------------------

    function Na__Shell__InitStatusBar() {
        var statusBar = document.getElementById('na-status-bar');
        if (!statusBar) return;
        statusBar.classList.add('na-hidden');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Init
    // -------------------------------------------------------------------------

    Na__ProfileTools__MainShell.Na__Shell__Init = function () {
        Na__Shell__InitBrandHeader();
        Na__Shell__InitStatusBar();
    };

    // endregion ----------------------------------------------------------------

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na__ProfileTools__MainShell.Na__Shell__Init);
    } else {
        Na__ProfileTools__MainShell.Na__Shell__Init();
    }

    window.Na__ProfileTools__MainShell = Na__ProfileTools__MainShell;

    // endregion ----------------------------------------------------------------
})();
