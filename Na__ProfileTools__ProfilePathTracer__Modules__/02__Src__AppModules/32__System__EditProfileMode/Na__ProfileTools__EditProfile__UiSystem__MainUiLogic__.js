/* =============================================================================
   NA PROFILE TOOLS - EDIT PROFILE MODE - UI SYSTEM - MAIN UI LOGIC
   =============================================================================
   FILE       : Na__ProfileTools__EditProfile__UiSystem__MainUiLogic__.js
   NAMESPACE  : window.Na__ProfileTools__EditProfile__Tab
   PURPOSE    : Edit Profile tab — live metadata editing with SVG preview,
                read-only geometry counts, save-to-file action.
                Implements the Na_TabRouter mount/unmount contract.
   ============================================================================= */

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var NA_BODY_ID        = 'na-tab-edit-profile-body';
    var na_is_mounted     = false;
    var na_current_key    = '';
    var na_is_saving      = false;

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function na_body()      { return document.getElementById(NA_BODY_ID); }
    function na_set_status(msg) {
        if (typeof window.Na__ProfilePathTracer__Ui__SetStatusFromBridge === 'function') {
            window.Na__ProfilePathTracer__Ui__SetStatusFromBridge(msg);
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Geometry Counts Helper
    // -------------------------------------------------------------------------

    function Na__Edit__ExtractGeometryCounts(record) {
        if (!record || !record.profileData) return { vertices: 0, edges: 0, faces: 0 };
        var assetData    = record.profileData.assetData || {};
        var profileBlock = assetData['Na__Asset__Profile2D'] || {};
        return {
            vertices : (profileBlock['Na__Geometry__Vertices'] || []).length,
            edges    : (profileBlock['Na__Geometry__Edges']    || []).length,
            faces    : (profileBlock['Na__Geometry__Faces']    || []).length
        };
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | SVG Preview HTML
    // -------------------------------------------------------------------------

    function Na__Edit__BuildSvgPreviewHtml(record) {
        var svgGen = window.Na__ProfilePathTracer__Viewport__SvgGenerator;
        if (!svgGen || !record) return '';

        var result = svgGen.Na__Svg__GenerateProfile(record, { toggleStates: {}, rotationStep: 0 });
        if (!result || !result.isValid) return '';

        return [
            '<div class="na-edit-profile__preview-wrap naViewportWrap">',
            '  <svg class="naViewportSvg na-edit-profile__preview-svg"',
            '       id="na-edit-preview-svg"',
            '       viewBox="' + (result.viewBox || '-120 -120 240 240') + '"',
            '       xmlns="http://www.w3.org/2000/svg">',
            result.svg,
            '  </svg>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Full Panel HTML
    // -------------------------------------------------------------------------

    function Na__Edit__BuildPanelHtml(record) {
        var assetData  = (record.profileData && record.profileData.assetData) || {};
        var meta       = assetData.meta || {};
        var assetMeta  = assetData['Na__Asset__Metadata'] || {};
        var counts     = Na__Edit__ExtractGeometryCounts(record);
        var store      = window.Na__ProfileTools__ProfileStore;
        var keywords   = store ? store.Na__Store__ProfileKeywords(record) : [];

        var name        = Na__Edit__Esc(assetMeta['Na__Asset__Name'] || record.displayName || '');
        var description = Na__Edit__Esc(assetMeta['Na__Asset__Description'] || '');
        var keywordsStr = Na__Edit__Esc(keywords.join(', '));
        var code        = Na__Edit__Esc(record.profileKey || '');
        var sourceFile  = Na__Edit__Esc(record.sourceFile || '');

        return [
            '<div class="na-edit-profile">',

            '  <div class="na-section na-edit-profile__preview-section">',
            Na__Edit__BuildSvgPreviewHtml(record),
            '  </div>',

            '  <div class="na-section">',
            '    <div class="na-edit-profile__geo-summary">',
            '      <span class="na-edit-profile__geo-item">Vertices: <strong>' + counts.vertices + '</strong></span>',
            '      <span class="na-edit-profile__geo-item">Edges: <strong>' + counts.edges + '</strong></span>',
            '      <span class="na-edit-profile__geo-item">Faces: <strong>' + counts.faces + '</strong></span>',
            '    </div>',
            '  </div>',

            '  <div class="na-section">',
            '    <div class="naFormRow">',
            '      <label for="na-edit-name">Name</label>',
            '      <input class="naInput" id="na-edit-name" type="text" value="' + name + '" placeholder="Profile name">',
            '    </div>',
            '    <div class="naFormRow">',
            '      <label for="na-edit-description">Description</label>',
            '      <textarea class="naTextarea" id="na-edit-description" rows="2" placeholder="Brief description">' + description + '</textarea>',
            '    </div>',
            '    <div class="naFormRow">',
            '      <label for="na-edit-keywords">Keywords</label>',
            '      <input class="naInput" id="na-edit-keywords" type="text" value="' + keywordsStr + '"',
            '             placeholder="keyword1, keyword2, ...">',
            '    </div>',
            '    <div class="naFormRow">',
            '      <label for="na-edit-profile-code">Profile Code</label>',
            '      <input class="naInput" id="na-edit-profile-code" type="text" value="' + code + '" placeholder="Profile code">',
            '    </div>',
            '    <div class="naFormRow">',
            '      <label>Source File</label>',
            '      <input class="naInputReadonly" type="text" value="' + sourceFile + '" readonly title="' + sourceFile + '">',
            '    </div>',
            '  </div>',

            '  <div class="na-section na-actions-section">',
            '    <button class="naButtonPrimary naButton" id="na-edit-save-btn">Save Changes</button>',
            '    <button class="naButtonSecondary naButton" id="na-edit-back-btn">Back to Gallery</button>',
            '  </div>',

            '</div>'
        ].join('');
    }

    function Na__Edit__Esc(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Empty State HTML
    // -------------------------------------------------------------------------

    function Na__Edit__BuildEmptyHtml() {
        return [
            '<div class="na-edit-profile-empty">',
            '  <p>No profile selected.</p>',
            '  <p>Open the <strong>Gallery</strong> tab and click a profile card to edit it.</p>',
            '  <button class="naButtonSecondary naButton" id="na-edit-go-gallery-btn">Go to Gallery</button>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    function Na__Edit__Render() {
        var body = na_body();
        if (!body) return;

        var store  = window.Na__ProfileTools__ProfileStore;
        var record = store ? store.Na__Store__GetSelectedRecord() : null;

        if (!record) {
            na_current_key = '';
            body.innerHTML = Na__Edit__BuildEmptyHtml();
            Na__Edit__WireEmptyState();
            return;
        }

        na_current_key = record.profileKey || store.Na__Store__GetSelectedKey();
        body.innerHTML = Na__Edit__BuildPanelHtml(record);
        Na__Edit__WireFormEvents(record);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Update SVG preview in place (without full re-render)
    // -------------------------------------------------------------------------

    function Na__Edit__RefreshPreview(record) {
        var svgGen = window.Na__ProfilePathTracer__Viewport__SvgGenerator;
        if (!svgGen || !record) return;
        var result = svgGen.Na__Svg__GenerateProfile(record, { toggleStates: {}, rotationStep: 0 });
        if (!result || !result.isValid) return;
        var svgEl = document.getElementById('na-edit-preview-svg');
        if (!svgEl) return;
        svgEl.setAttribute('viewBox', result.viewBox || '-120 -120 240 240');
        svgEl.innerHTML = result.svg;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Form Event Wiring
    // -------------------------------------------------------------------------

    function Na__Edit__WireFormEvents(record) {
        var nameEl     = document.getElementById('na-edit-name');
        var descEl     = document.getElementById('na-edit-description');
        var kwEl       = document.getElementById('na-edit-keywords');
        var saveBtn    = document.getElementById('na-edit-save-btn');
        var backBtn    = document.getElementById('na-edit-back-btn');

        var store = window.Na__ProfileTools__ProfileStore;
        var key   = record.profileKey || na_current_key;

        function na_apply_patch() {
            if (!store) return;
            var kwRaw    = kwEl ? kwEl.value : '';
            var keywords = kwRaw.split(',').map(function (k) { return k.trim(); }).filter(Boolean);
            store.Na__Store__ApplyMetaPatch(key, {
                name        : nameEl    ? nameEl.value    : record.displayName,
                description : descEl    ? descEl.value    : '',
                keywords    : keywords
            });
            var updatedRecord = store.Na__Store__GetProfile(key);
            if (updatedRecord) Na__Edit__RefreshPreview(updatedRecord);
        }

        if (nameEl)  nameEl.addEventListener('input',  na_apply_patch);
        if (descEl)  descEl.addEventListener('input',  na_apply_patch);
        if (kwEl)    kwEl.addEventListener('input',    na_apply_patch);

        if (saveBtn) {
            saveBtn.addEventListener('click', function () {
                if (na_is_saving) return;
                na_is_saving = true;
                saveBtn.disabled = true;
                saveBtn.textContent = 'Saving...';

                var kwRaw    = kwEl ? kwEl.value : '';
                var keywords = kwRaw.split(',').map(function (k) { return k.trim(); }).filter(Boolean);

                var payload = {
                    profileKey  : key,
                    sourceFile  : record.sourceFile || '',
                    name        : nameEl ? nameEl.value : '',
                    description : descEl ? descEl.value : '',
                    keywords    : keywords
                };

                if (window.Na__EditProfile__Bridge__Save) {
                    window.Na__EditProfile__Bridge__Save(payload);
                }
            });
        }

        if (backBtn) {
            backBtn.addEventListener('click', function () {
                if (window.Na_TabRouter) window.Na_TabRouter.na_activateTab('gallery');
            });
        }
    }

    function Na__Edit__WireEmptyState() {
        var goBtn = document.getElementById('na-edit-go-gallery-btn');
        if (goBtn) {
            goBtn.addEventListener('click', function () {
                if (window.Na_TabRouter) window.Na_TabRouter.na_activateTab('gallery');
            });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Store Subscriptions
    // -------------------------------------------------------------------------

    function Na__Edit__OnSelectedChanged(payload) {
        if (!na_is_mounted) return;
        na_is_saving = false;
        Na__Edit__Render();
    }

    function Na__Edit__OnMetaUpdated(payload) {
        if (!na_is_mounted || payload.key !== na_current_key) return;
        Na__Edit__RefreshPreview(payload.record);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Save Result Receiver
    // -------------------------------------------------------------------------

    function na_receive_save_result(result) {
        na_is_saving = false;
        var saveBtn = document.getElementById('na-edit-save-btn');
        if (saveBtn) {
            saveBtn.disabled = false;
            saveBtn.textContent = 'Save Changes';
        }

        if (!result) return;

        if (result.isSaved) {
            na_set_status(result.statusMessage || 'Profile saved.');
        } else {
            na_set_status(result.statusMessage || 'Save failed.');
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Lifecycle
    // -------------------------------------------------------------------------

    function na_mount() {
        na_is_mounted = true;
        na_is_saving  = false;

        var appCtx = window.Na_AppContext;
        if (appCtx) {
            appCtx.na_subscribe('na_selected_changed',    Na__Edit__OnSelectedChanged);
            appCtx.na_subscribe('na_profile_meta_updated', Na__Edit__OnMetaUpdated);
        }

        Na__Edit__Render();
    }

    function na_unmount() {
        na_is_mounted = false;
        var body = na_body();
        if (body) body.innerHTML = '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__EditProfile__Tab = {
        na_mount:             na_mount,
        na_unmount:           na_unmount,
        na_receive_save_result: na_receive_save_result
    };

    // endregion ----------------------------------------------------------------
})();
