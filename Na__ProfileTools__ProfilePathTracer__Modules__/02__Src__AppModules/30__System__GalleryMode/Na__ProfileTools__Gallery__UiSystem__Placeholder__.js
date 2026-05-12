/* =============================================================================
   NA PROFILE TOOLS - GALLERY MODE - UI SYSTEM - PLACEHOLDER
   =============================================================================
   FILE       : Na__ProfileTools__Gallery__UiSystem__Placeholder__.js
   NAMESPACE  : window.Na__ProfileTools__Gallery__Tab
   PURPOSE    : Stub mount/unmount contract for the Gallery tab.
                Renders a 'Coming soon' placeholder panel.
   ============================================================================= */

(function() {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Rendering
    // -------------------------------------------------------------------------

    function Na__Gallery__RenderPlaceholder() {
        const galleryBody = document.getElementById('na-tab-gallery-body');
        if (!galleryBody) return;

        galleryBody.innerHTML = [
            '<div class="na-gallery-placeholder">',
            '  <div class="na-gallery-placeholder__icon">&#128444;</div>',
            '  <h2 class="na-gallery-placeholder__title">Profile Gallery</h2>',
            '  <p class="na-gallery-placeholder__copy">',
            '    Visual profile selection is coming soon.',
            '    You will be able to browse and select profiles by thumbnail here.',
            '  </p>',
            '  <div class="na-gallery-grid-stub">',
            '    <div class="na-gallery-grid-stub__cell"></div>',
            '    <div class="na-gallery-grid-stub__cell"></div>',
            '    <div class="na-gallery-grid-stub__cell"></div>',
            '    <div class="na-gallery-grid-stub__cell"></div>',
            '  </div>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Lifecycle
    // -------------------------------------------------------------------------

    function na_mount() {
        Na__Gallery__RenderPlaceholder();
    }

    function na_unmount() {
        const galleryBody = document.getElementById('na-tab-gallery-body');
        if (galleryBody) galleryBody.innerHTML = '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Export
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__Gallery__Tab = {
        na_mount: na_mount,
        na_unmount: na_unmount
    };

    // endregion ----------------------------------------------------------------
})();
