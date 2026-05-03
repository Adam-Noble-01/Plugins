// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - APP MAIN SHELL (top-bar / brand chrome)
// =============================================================================
//
// FILE       : Na__AssemblyStudio__AppCore__UiSystem__MainShell__.js
// NAMESPACE  : window.Na_MainShell
// AUTHOR     : Noble Architecture
// PURPOSE    : Tiny chrome controller for the top bar (logo + wordmark) and
//              the tab strip's right-aligned action buttons. Gives AppContext
//              a stable `Na_MainShell.na_set_app_title(text)` if we ever want
//              to swap the wordmark dynamically (e.g. in dev builds).
//
// The actual top-bar HTML lives in Na__AssemblyStudio__UiLayout__.html and the
// styling lives in 03__Style__AppStylesheets/...UiFeature__Styles__BrandHeader.
// =============================================================================

(function () {
    'use strict';

    var Na_MainShell = {};

    var NA_BRAND_TITLE_ID    = 'na-brand-title';
    var NA_BRAND_SUBTITLE_ID = 'na-brand-subtitle';

    Na_MainShell.na_set_app_title = function (text) {
        var el = document.getElementById(NA_BRAND_TITLE_ID);
        if (el) el.textContent = String(text || '');
    };

    Na_MainShell.na_set_app_subtitle = function (text) {
        var el = document.getElementById(NA_BRAND_SUBTITLE_ID);
        if (el) el.textContent = String(text || '');
    };

    Na_MainShell.na_init = function () {
        // Chrome is fully markup-driven today; this hook exists so future
        // dynamic chrome (theme switching, brand variants) has a home.
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', Na_MainShell.na_init);
    } else {
        Na_MainShell.na_init();
    }

    window.Na_MainShell = Na_MainShell;
})();
