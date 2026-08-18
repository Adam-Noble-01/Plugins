/* =============================================================================
   NA PROFILE TOOLS - EDIT PROFILE MODE - UI SYSTEM - MAIN UI LOGIC
   =============================================================================
   FILE       : Na__ProfileTools__EditProfile__UiSystem__MainUiLogic__.js
   NAMESPACE  : window.Na__ProfileTools__EditProfile__Tab
   PURPOSE    : Edit Profile tab — live metadata editing with SVG preview,
                read-only geometry counts, save-to-file action, plus the two
                destructive library actions: geometry re-capture and delete.
                Implements the Na_TabRouter mount/unmount contract.

   DANGER ZONE CONTRACT
                Re-capture and delete both rewrite or remove a file in the
                user's library, and both sit one stray click away from the Save
                button. So neither fires on its first click: the button opens an
                inline confirmation naming exactly what is about to happen, and
                only the second, differently-placed click reaches Ruby. Nothing
                is sent, no model tool is armed, and no file is touched until
                that confirmation is given.
   ============================================================================= */

(function () {
    'use strict';

    // -------------------------------------------------------------------------
    // REGION | Module State
    // -------------------------------------------------------------------------

    var NA_BODY_ID         = 'na-tab-edit-profile-body';
    var NA_DANGER_ZONE_ID  = 'na-edit-danger-zone';

    var na_is_mounted      = false;
    var na_current_key     = '';
    var na_is_saving       = false;

    // '' | 'reselect' | 'delete' — which confirmation gate is open. Advisory
    // only: an open gate has sent nothing to Ruby.
    var na_pending_confirm = '';

    // '' | 'reselect' | 'delete' — which destructive request is mid-flight and
    // waiting on Ruby. Blocks every other action until a result arrives.
    var na_danger_request  = '';

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | DOM Helpers
    // -------------------------------------------------------------------------

    function na_body()        { return document.getElementById(NA_BODY_ID); }
    function na_danger_zone() { return document.getElementById(NA_DANGER_ZONE_ID); }

    function na_set_status(msg) {
        if (typeof window.Na__ProfilePathTracer__Ui__SetStatusFromBridge === 'function') {
            window.Na__ProfilePathTracer__Ui__SetStatusFromBridge(msg);
        }
    }

    function na_current_record() {
        var store = window.Na__ProfileTools__ProfileStore;
        return store ? store.Na__Store__GetSelectedRecord() : null;
    }

    function na_is_request_in_flight() {
        return na_is_saving || na_danger_request !== '';
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
            '    <button class="naButtonSecondary naButton" id="na-edit-flip-btn"',
            '            title="Mirror this profile left-right about its datum and write it back to the library file, so the whole library can share one handing. Saves any edits above at the same time. Note: runs already placed with a custom insert point will need that point re-picked.">',
            '      ⇄ Flip Profile',
            '    </button>',
            '    <button class="naButtonSecondary naButton" id="na-edit-back-btn">Back to Gallery</button>',
            '  </div>',

            // Deliberately not a .na-section: that class's :last-child rule
            // strips the bottom border this card needs to read as a closed box.
            '  <div class="na-edit-danger" id="' + NA_DANGER_ZONE_ID + '">',
            Na__Edit__BuildDangerZoneHtml(record),
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
    // REGION | Danger Zone HTML
    // -------------------------------------------------------------------------

    function Na__Edit__BuildDangerZoneHtml(record) {
        if (na_danger_request === 'reselect') return Na__Edit__BuildReselectWaitingHtml();
        if (na_danger_request === 'delete')   return Na__Edit__BuildDeleteBusyHtml();
        if (na_pending_confirm === 'reselect') return Na__Edit__BuildReselectConfirmHtml();
        if (na_pending_confirm === 'delete')   return Na__Edit__BuildDeleteConfirmHtml(record);
        return Na__Edit__BuildDangerIdleHtml();
    }

    function Na__Edit__BuildDangerIdleHtml() {
        return [
            '<div class="na-section-header"><h2>Rebuild &amp; Remove</h2></div>',
            '<p class="na-edit-danger__lead">',
            '  Both actions below change this profile&rsquo;s data file on disk and ask you to confirm first.',
            '</p>',
            '<div class="na-edit-danger__actions">',
            '  <button class="naButtonSecondary naButton na-edit-danger__trigger" id="na-edit-reselect-btn"',
            '          title="Re-run the Create Profile capture against this same library file — pick a new face and a new origin point, keeping the profile code, name, description and keywords.">',
            '    ⟳ Re-select Profile Geometry',
            '  </button>',
            '  <button class="naButtonDanger naButton na-edit-danger__trigger" id="na-edit-delete-btn"',
            '          title="Permanently delete this profile\'s data file from the library.">',
            '    🗑 Delete Profile',
            '  </button>',
            '</div>'
        ].join('');
    }

    function Na__Edit__BuildReselectConfirmHtml() {
        return [
            '<div class="na-edit-confirm na-edit-confirm--warn">',
            '  <div class="na-edit-confirm__title">Are you sure you want to re-select this profile&rsquo;s geometry?</div>',
            '  <div class="na-edit-confirm__body">',
            '    <p>This <strong>overwrites the geometry stored in this profile&rsquo;s data file</strong> with whatever is',
            '       currently selected in SketchUp, and re-picks its origin point.</p>',
            '    <ul>',
            '      <li>Kept: profile code, name, description, keywords and all other metadata.</li>',
            '      <li>Replaced: the 2D profile and 3D mesh blocks, including edge colours and soft/smooth flags.</li>',
            '      <li>A <code>.bak</code> copy of the current file is written before anything is overwritten.</li>',
            '      <li>Runs already placed in the model are <strong>not</strong> rebuilt.</li>',
            '    </ul>',
            '    <p class="na-edit-confirm__prompt">Before continuing: select the replacement closed face in SketchUp.',
            '       You will then be asked to click the new origin point — nothing is written until you do.</p>',
            '  </div>',
            '  <div class="na-edit-confirm__actions">',
            '    <button class="naButtonSecondary naButton" id="na-edit-confirm-cancel-btn">Cancel</button>',
            '    <button class="naButtonWarn naButton" id="na-edit-confirm-reselect-btn">Yes &mdash; re-select geometry</button>',
            '  </div>',
            '</div>'
        ].join('');
    }

    function Na__Edit__BuildDeleteConfirmHtml(record) {
        var displayName = Na__Edit__Esc((record && (record.displayName || record.profileKey)) || 'this profile');
        var sourceFile  = Na__Edit__Esc((record && record.sourceFile) || '');

        return [
            '<div class="na-edit-confirm na-edit-confirm--danger">',
            '  <div class="na-edit-confirm__title">Permanently delete &ldquo;' + displayName + '&rdquo;?</div>',
            '  <div class="na-edit-confirm__body">',
            '    <p class="na-edit-confirm__irreversible">This is irreversible. The data file is deleted from disk and cannot be recovered from within this plugin.</p>',
            '    <p class="na-edit-confirm__path">' + sourceFile + '</p>',
            '    <ul>',
            '      <li>The profile is removed from the Gallery and can no longer be applied or regenerated.</li>',
            '      <li>Geometry already placed in the model is left alone, but loses its source profile.</li>',
            '    </ul>',
            '  </div>',
            '  <div class="na-edit-confirm__actions">',
            '    <button class="naButtonSecondary naButton" id="na-edit-confirm-cancel-btn">Cancel</button>',
            '    <button class="naButtonDanger naButton" id="na-edit-confirm-delete-btn">Yes, delete permanently</button>',
            '  </div>',
            '</div>'
        ].join('');
    }

    function Na__Edit__BuildReselectWaitingHtml() {
        return [
            '<div class="na-edit-confirm na-edit-confirm--busy">',
            '  <div class="na-edit-confirm__title">Waiting for the new origin point&hellip;</div>',
            '  <div class="na-edit-confirm__body">',
            '    <p>Switch to the SketchUp window and click the point that should become this profile&rsquo;s',
            '       0,0 datum. Press <strong>ESC</strong> in the model to cancel — the file is only written',
            '       once you click.</p>',
            '  </div>',
            '</div>'
        ].join('');
    }

    function Na__Edit__BuildDeleteBusyHtml() {
        return [
            '<div class="na-edit-confirm na-edit-confirm--busy">',
            '  <div class="na-edit-confirm__title">Deleting profile&hellip;</div>',
            '</div>'
        ].join('');
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

    // Re-renders only the danger zone. A full render would rebuild the SVG and
    // reset the scroll position for what is a state change in one small block.
    function Na__Edit__RenderDangerZone() {
        var zone = na_danger_zone();
        if (!zone) return;
        zone.innerHTML = Na__Edit__BuildDangerZoneHtml(na_current_record());
        Na__Edit__WireDangerZone();
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
    // REGION | Form Field Readers
    // -------------------------------------------------------------------------

    // Falls back to the record rather than to empty strings when a field is not
    // in the DOM. Every write carries all three metadata fields, so an absent
    // input reading as "" would blank a description or wipe keywords on disk.
    function Na__Edit__ReadFormFields(record) {
        var nameEl = document.getElementById('na-edit-name');
        var descEl = document.getElementById('na-edit-description');
        var kwEl   = document.getElementById('na-edit-keywords');

        var assetData = (record && record.profileData && record.profileData.assetData) || {};
        var assetMeta = assetData['Na__Asset__Metadata'] || {};
        var store     = window.Na__ProfileTools__ProfileStore;

        var keywords;
        if (kwEl) {
            keywords = kwEl.value.split(',').map(function (k) { return k.trim(); }).filter(Boolean);
        } else {
            keywords = store ? store.Na__Store__ProfileKeywords(record) : [];
        }

        return {
            name        : nameEl ? nameEl.value : (assetMeta['Na__Asset__Name'] || (record && record.displayName) || ''),
            description : descEl ? descEl.value : (assetMeta['Na__Asset__Description'] || ''),
            keywords    : keywords
        };
    }

    // Every write carries the metadata currently on screen, so no destructive
    // action can silently discard edits the user has typed but not yet saved.
    function Na__Edit__BuildWritePayload(record, extraFields) {
        var fields  = Na__Edit__ReadFormFields(record);
        var payload = {
            profileKey  : (record && record.profileKey) || na_current_key,
            sourceFile  : (record && record.sourceFile) || '',
            name        : fields.name,
            description : fields.description,
            keywords    : fields.keywords
        };

        if (extraFields) {
            Object.keys(extraFields).forEach(function (fieldKey) {
                payload[fieldKey] = extraFields[fieldKey];
            });
        }
        return payload;
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Form Event Wiring
    // -------------------------------------------------------------------------

    function Na__Edit__WireFormEvents(record) {
        var nameEl  = document.getElementById('na-edit-name');
        var descEl  = document.getElementById('na-edit-description');
        var kwEl    = document.getElementById('na-edit-keywords');
        var saveBtn = document.getElementById('na-edit-save-btn');
        var flipBtn = document.getElementById('na-edit-flip-btn');
        var backBtn = document.getElementById('na-edit-back-btn');

        var store = window.Na__ProfileTools__ProfileStore;
        var key   = record.profileKey || na_current_key;

        function na_apply_patch() {
            if (!store) return;
            var fields = Na__Edit__ReadFormFields(record);
            store.Na__Store__ApplyMetaPatch(key, {
                name        : fields.name,
                description : fields.description,
                keywords    : fields.keywords
            });
            var updatedRecord = store.Na__Store__GetProfile(key);
            if (updatedRecord) Na__Edit__RefreshPreview(updatedRecord);
        }

        if (nameEl)  nameEl.addEventListener('input',  na_apply_patch);
        if (descEl)  descEl.addEventListener('input',  na_apply_patch);
        if (kwEl)    kwEl.addEventListener('input',    na_apply_patch);

        // na_is_saving gates BOTH buttons, so any dispatch that never reaches Ruby
        // must release it here — otherwise one dead click leaves Save and Flip
        // disabled for the rest of the session, waiting on a result that is never
        // coming. The bridge returns false when SketchUp is not connected.
        function na_dispatch_write(button, busyLabel, idleLabel, flipHorizontal) {
            if (na_is_request_in_flight()) return;
            na_is_saving = true;
            button.disabled = true;
            button.textContent = busyLabel;

            // Carried on the same write as the metadata, so flipping never
            // throws away edits the user has typed but not yet saved.
            var payload = Na__Edit__BuildWritePayload(record, { flipHorizontal: flipHorizontal === true });

            var isDispatched = window.Na__EditProfile__Bridge__Save
                ? window.Na__EditProfile__Bridge__Save(payload)
                : false;
            if (isDispatched) return;

            na_is_saving = false;
            button.disabled = false;
            button.textContent = idleLabel;
            na_set_status('Save bridge is not available — nothing was written.');
        }

        if (saveBtn) {
            saveBtn.addEventListener('click', function () {
                na_dispatch_write(saveBtn, 'Saving...', 'Save Changes', false);
            });
        }

        if (flipBtn) {
            flipBtn.addEventListener('click', function () {
                na_dispatch_write(flipBtn, 'Flipping...', '⇄ Flip Profile', true);
            });
        }

        if (backBtn) {
            backBtn.addEventListener('click', function () {
                if (window.Na_TabRouter) window.Na_TabRouter.na_activateTab('gallery');
            });
        }

        Na__Edit__WireDangerZone();
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
    // REGION | Danger Zone Wiring
    // -------------------------------------------------------------------------

    function Na__Edit__WireDangerZone() {
        Na__Edit__WireDangerTrigger('na-edit-reselect-btn', 'reselect');
        Na__Edit__WireDangerTrigger('na-edit-delete-btn',   'delete');

        var cancelBtn = document.getElementById('na-edit-confirm-cancel-btn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', function () {
                na_pending_confirm = '';
                Na__Edit__RenderDangerZone();
                na_set_status('Cancelled — nothing was changed.');
            });
        }

        var confirmReselectBtn = document.getElementById('na-edit-confirm-reselect-btn');
        if (confirmReselectBtn) {
            confirmReselectBtn.addEventListener('click', Na__Edit__DispatchReselect);
        }

        var confirmDeleteBtn = document.getElementById('na-edit-confirm-delete-btn');
        if (confirmDeleteBtn) {
            confirmDeleteBtn.addEventListener('click', Na__Edit__DispatchDelete);
        }
    }

    // Opening a gate is purely local — nothing reaches Ruby and no model tool is
    // armed, so a mis-click here costs one Cancel.
    function Na__Edit__WireDangerTrigger(buttonId, confirmMode) {
        var button = document.getElementById(buttonId);
        if (!button) return;
        button.addEventListener('click', function () {
            if (na_is_request_in_flight()) return;
            na_pending_confirm = confirmMode;
            Na__Edit__RenderDangerZone();
        });
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Danger Zone Dispatch
    // -------------------------------------------------------------------------

    function Na__Edit__DispatchReselect() {
        var record = na_current_record();
        if (!record) {
            na_pending_confirm = '';
            Na__Edit__RenderDangerZone();
            na_set_status('No profile is loaded — nothing to re-capture.');
            return;
        }

        na_pending_confirm = '';
        na_danger_request  = 'reselect';
        Na__Edit__RenderDangerZone();

        var isDispatched = window.Na__EditProfile__Bridge__ReplaceGeometry
            ? window.Na__EditProfile__Bridge__ReplaceGeometry(Na__Edit__BuildWritePayload(record))
            : false;
        if (isDispatched) return;

        na_danger_request = '';
        Na__Edit__RenderDangerZone();
        na_set_status('Geometry re-capture bridge is not available — nothing was changed.');
    }

    function Na__Edit__DispatchDelete() {
        var record = na_current_record();
        if (!record) {
            na_pending_confirm = '';
            Na__Edit__RenderDangerZone();
            na_set_status('No profile is loaded — nothing to delete.');
            return;
        }

        na_pending_confirm = '';
        na_danger_request  = 'delete';
        Na__Edit__RenderDangerZone();

        var isDispatched = window.Na__EditProfile__Bridge__DeleteProfile
            ? window.Na__EditProfile__Bridge__DeleteProfile({
                  profileKey : record.profileKey || na_current_key,
                  sourceFile : record.sourceFile || ''
              })
            : false;
        if (isDispatched) return;

        na_danger_request = '';
        Na__Edit__RenderDangerZone();
        na_set_status('Delete bridge is not available — nothing was deleted.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Store Subscriptions
    // -------------------------------------------------------------------------

    function Na__Edit__OnSelectedChanged(payload) {
        if (!na_is_mounted) return;
        na_is_saving = false;

        // A different profile arriving mid-gate would leave the confirmation
        // describing one file while the panel shows another, so the gate closes
        // with the switch. An in-flight request is left alone: its result still
        // has to land.
        if (payload && payload.key !== na_current_key) na_pending_confirm = '';

        Na__Edit__Render();
    }

    function Na__Edit__OnMetaUpdated(payload) {
        if (!na_is_mounted || payload.key !== na_current_key) return;
        Na__Edit__RefreshPreview(payload.record);
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Result Receivers
    // -------------------------------------------------------------------------

    function na_receive_save_result(result) {
        na_is_saving = false;

        var saveBtn = document.getElementById('na-edit-save-btn');
        if (saveBtn) {
            saveBtn.disabled = false;
            saveBtn.textContent = 'Save Changes';
        }

        var flipBtn = document.getElementById('na-edit-flip-btn');
        if (flipBtn) {
            flipBtn.disabled = false;
            flipBtn.textContent = '⇄ Flip Profile';
        }

        if (!result) return;

        // No redraw needed here: the bridge hands the freshly re-parsed record to
        // Na__Store__UpdateRecord first, and its na_selected_changed dispatch has
        // already re-rendered this panel (and the Gallery card) from disk truth.
        if (result.isSaved) {
            na_set_status(result.statusMessage || 'Profile saved.');
        } else {
            na_set_status(result.statusMessage || result.reason || 'Save failed.');
        }
    }

    function na_receive_replace_geometry_result(result) {
        if (!result) {
            na_danger_request = '';
            Na__Edit__RenderDangerZone();
            return;
        }

        // The arming call answers isPending: Ruby has accepted the request and
        // handed the user to the origin picker. The real result arrives on the
        // model click, so the waiting card stays up.
        if (result.isPending === true) {
            na_set_status(result.statusMessage || 'Click in model to set the new origin point.');
            return;
        }

        na_danger_request  = '';
        na_pending_confirm = '';
        Na__Edit__RenderDangerZone();
        na_set_status(result.statusMessage || result.reason || 'Geometry re-capture finished.');
    }

    function na_receive_delete_result(result) {
        na_danger_request  = '';
        na_pending_confirm = '';

        if (!result) {
            Na__Edit__RenderDangerZone();
            return;
        }

        if (result.isDeleted) {
            // Nothing left to edit — the record this panel was bound to no
            // longer exists on disk or in the store.
            na_current_key = '';
            if (window.Na_TabRouter) window.Na_TabRouter.na_activateTab('gallery');
            na_set_status(result.statusMessage || 'Profile deleted.');
            return;
        }

        Na__Edit__RenderDangerZone();
        na_set_status(result.statusMessage || result.reason || 'Delete failed.');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Lifecycle
    // -------------------------------------------------------------------------

    function na_mount() {
        na_is_mounted      = true;
        na_is_saving       = false;
        na_pending_confirm = '';

        var appCtx = window.Na_AppContext;
        if (appCtx) {
            appCtx.na_subscribe('na_selected_changed',    Na__Edit__OnSelectedChanged);
            appCtx.na_subscribe('na_profile_meta_updated', Na__Edit__OnMetaUpdated);
        }

        Na__Edit__Render();
    }

    // na_danger_request is deliberately NOT cleared: the origin picker can still
    // be live in the model after the user tabs away, and its result must find
    // the panel in the state that produced it.
    function na_unmount() {
        na_is_mounted      = false;
        na_pending_confirm = '';
        var body = na_body();
        if (body) body.innerHTML = '';
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Public Exports
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__EditProfile__Tab = {
        na_mount:                            na_mount,
        na_unmount:                          na_unmount,
        na_receive_save_result:              na_receive_save_result,
        na_receive_replace_geometry_result:  na_receive_replace_geometry_result,
        na_receive_delete_result:            na_receive_delete_result
    };

    // endregion ----------------------------------------------------------------
})();
