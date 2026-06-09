// =============================================================================
// NA PROFILE TOOLS - CREATE NEW PROFILE - UI SYSTEM - MAIN UI LOGIC
// =============================================================================
// FILE       : Na__ProfileTools__CreateNewProfile__UiSystem__MainUiLogic__.js
// NAMESPACE  : window.Na__ProfileTools__CreateNewProfile__Tab
// PURPOSE    : Owns the Create New Profile tab workflow.
//              Instruction state -> Validate -> Form -> Save.
//              Owns ReceiveExportValidation + ReceiveSaveProfileResult callbacks.
// =============================================================================

(function () {
    'use strict';

    var na_state = { isValidated: false, validationResult: null, isSaving: false };

    function Na__GetBody()      { return document.getElementById('na-create-profile-tab-body'); }
    function Na__SetStatus(msg) {
        var el  = document.getElementById('na-status-message');
        var bar = document.getElementById('na-status-bar');
        if (el)  el.textContent = msg || '';
        if (bar) bar.classList.toggle('na-hidden', !msg);
    }

    // -------------------------------------------------------------------------
    // REGION | HTML Builders
    // -------------------------------------------------------------------------

    function Na__HtmlInstructions() {
        return [
            '<div class="na-section">',
            '  <div class="na-section-header"><h2>Create a New Profile</h2></div>',
            '  <ol class="na-create-profile-steps">',
            '    <li>In SketchUp, <strong>select a closed face</strong> that represents the profile cross-section geometry.</li>',
            '    <li>Click <strong>Validate Selection</strong> to confirm it is suitable for export.</li>',
            '    <li>Fill in the profile details and click <strong>Save Profile Data File</strong>.</li>',
            '  </ol>',
            '</div>',
            '<div class="na-section na-actions-section">',
            '  <button class="naButton naButtonPrimary" id="naBtnValidateForExport">Validate Selection</button>',
            '</div>'
        ].join('');
    }

    function Na__HtmlTimestamp() {
        var now = new Date();
        var d   = String(now.getDate()).padStart(2, '0');
        var months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        var m   = months[now.getMonth()];
        var y   = now.getFullYear();
        var hh  = String(now.getHours()).padStart(2, '0');
        var mm  = String(now.getMinutes()).padStart(2, '0');
        return d + '-' + m + '-' + y + '__' + hh + ':' + mm;
    }

    function Na__HtmlSvgPreview(v) {
        if (!Array.isArray(v.previewPoints) || v.previewPoints.length < 2) return '';
        var gen = window.Na__ProfilePathTracer__Viewport__SvgGenerator;
        if (!gen) return '';
        var pts      = v.previewPoints;
        var vertices = pts.map(function (p, i) { return { VertexId: 'V' + String(i+1).padStart(3,'0'), PosY_mm: Number(p[0]), PosZ_mm: Number(p[1]) }; });
        var edges    = vertices.map(function (vx, i) { var nx = (i+1)%vertices.length; return { EdgeId: 'E'+String(i+1).padStart(3,'0'), StartVertex: vx.VertexId, EndVertex: vertices[nx].VertexId }; });
        var me       = edges.map(function (e) { return { EdgeId: e.EdgeId, StartVertex: e.StartVertex, EndVertex: e.EndVertex, IsSoft: false, IsSmooth: false, IsHidden: false, CastsShadows: true, EdgeMaterialName: '', EdgeColourId: '', EdgeColourHex: '' }; });
        var rec = { profileData: { type: 'na_unified_asset', assetData: { meta: {}, Na__Asset__Metadata: {}, Na__Asset__Profile2D: { Na__Geometry__Vertices: vertices, Na__Geometry__Edges: edges, Na__Geometry__Faces: [{ FaceId: 'F001', OuterLoopVertices: vertices.map(function (vx) { return vx.VertexId; }) }] }, Na__Asset__Mesh3D: { Na__Geometry__Edges: me } } } };
        var r = gen.Na__Svg__GenerateProfile(rec, { toggleStates: {}, rotationStep: 0 });
        return '<div class="naViewportWrap" style="margin-bottom:12px;"><svg class="naViewportSvg" viewBox="' + (r.viewBox||'-120 -120 240 240') + '">' + (r.svg||'') + '</svg></div>';
    }

    function Na__HtmlForm(v) {
        var summary = 'Selection: ' + (v.faceCount||0) + ' faces, ' + (v.edgeCount||0) + ' edges, ' + (v.vertexCount||0) + ' vertices';
        return [
            '<div class="na-section">',
            '  <div class="na-section-header"><h2>Geometry Summary</h2></div>',
            '  <div class="naValidationSummary">' + summary + '</div>',
            Na__HtmlSvgPreview(v),
            '</div>',
            '<div class="na-section">',
            '  <div class="na-section-header"><h2>Profile Details</h2></div>',
            '  <div class="naFormRow"><label for="naMetaProfileName">Profile Name</label><input class="naInput" id="naMetaProfileName" type="text" placeholder="e.g. Gutter Box 200x100"></div>',
            '  <div class="naFormRow"><label for="naMetaDescription">Description</label><textarea class="naTextarea" id="naMetaDescription" rows="2" placeholder="A brief description of this profile shape"></textarea></div>',
            '  <div class="naFormRow"><label for="naMetaKeywords">Keywords</label><input class="naInput" id="naMetaKeywords" type="text" placeholder="gutter, box, 200mm (comma separated)"></div>',
            '  <div class="naFormRow"><label for="naMetaProfileId">Profile ID</label><input class="naInput" id="naMetaProfileId" type="text" placeholder="PRF001_GutterBox__200x100"></div>',
            '  <div class="naFormRow"><label>Timestamp</label><input class="naInputReadonly" type="text" value="' + Na__HtmlTimestamp() + '" readonly></div>',
            '  <div class="naFormRow"><label>Units</label><input class="naInputReadonly" type="text" value="millimetres" readonly></div>',
            '</div>',
            '<div class="na-section na-actions-section">',
            '  <button class="naButtonSuccess" id="naBtnSaveProfile">Save Profile Data File</button>',
            '  <button class="naButtonSecondary" id="naBtnResetCreateProfile">Start Over</button>',
            '</div>'
        ].join('');
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Event Wiring
    // -------------------------------------------------------------------------

    function Na__WireInstructions() {
        var btn = document.getElementById('naBtnValidateForExport');
        if (!btn) return;
        btn.addEventListener('click', function () {
            Na__SetStatus('Validating selection for profile export...');
            if (window.Na__ProfilePathTracer__Bridge__ValidateForExport) {
                window.Na__ProfilePathTracer__Bridge__ValidateForExport();
            } else {
                Na__SetStatus('Export validation bridge unavailable.');
            }
        });
    }

    function Na__WireForm() {
        var btnSave  = document.getElementById('naBtnSaveProfile');
        var btnReset = document.getElementById('naBtnResetCreateProfile');
        if (btnSave) {
            btnSave.addEventListener('click', function () {
                var name     = (document.getElementById('naMetaProfileName') || {}).value || '';
                var desc     = (document.getElementById('naMetaDescription') || {}).value || '';
                var kwRaw    = (document.getElementById('naMetaKeywords')    || {}).value || '';
                var id       = (document.getElementById('naMetaProfileId')   || {}).value || '';
                var keywords = kwRaw.split(',').map(function (k) { return k.trim(); }).filter(function (k) { return k.length > 0; });
                if (!name && !id) { Na__SetStatus('Profile Name or Profile ID is required before saving.'); return; }
                na_state.isSaving = true;
                Na__SetStatus('Saving profile...');
                if (window.Na__ProfilePathTracer__Bridge__SaveProfile) {
                    window.Na__ProfilePathTracer__Bridge__SaveProfile({ Meta_ProfileName: name, Meta_Description: desc, Meta_Keywords: keywords, Meta_ProfileId: id });
                }
            });
        }
        if (btnReset) {
            btnReset.addEventListener('click', function () {
                na_state.isValidated = false; na_state.validationResult = null; na_state.isSaving = false;
                Na__Render();
                Na__SetStatus('Reset. Select geometry in SketchUp and validate again.');
            });
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Render
    // -------------------------------------------------------------------------

    function Na__Render() {
        var body = Na__GetBody();
        if (!body) return;
        if (!na_state.isValidated) {
            body.innerHTML = Na__HtmlInstructions();
            Na__WireInstructions();
        } else {
            body.innerHTML = Na__HtmlForm(na_state.validationResult || {});
            Na__WireForm();
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Tab Lifecycle
    // -------------------------------------------------------------------------

    function na_mount()   { Na__Render(); }
    function na_unmount() { na_state.isValidated = false; na_state.validationResult = null; na_state.isSaving = false; }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Ruby -> JS Callbacks
    // -------------------------------------------------------------------------

    function Na__ReceiveExportValidation(result) {
        if (!result || typeof result !== 'object') { Na__SetStatus('Export validation returned no result.'); return; }
        if (result.isPendingOrigin === true) { Na__SetStatus(result.statusMessage || 'Click in model to place 00__OriginPoint first.'); return; }
        if (!result.isValid) { Na__SetStatus(result.statusMessage || ('Cannot create profile: ' + (result.reason || 'Unknown error.'))); return; }
        na_state.isValidated = true; na_state.validationResult = result;
        if (window.Na_TabRouter && window.Na_TabRouter.na_get_active_tab() !== 'create-profile') {
            window.Na_TabRouter.na_activateTab('create-profile');
        } else {
            Na__Render();
        }
        Na__SetStatus(result.statusMessage || 'Validation passed. Fill in the profile details and save.');
    }

    function Na__ReceiveSaveProfileResult(result) {
        na_state.isSaving = false;
        if (!result || typeof result !== 'object') { Na__SetStatus('Save returned no result.'); return; }
        if (result.isPending === true) { Na__SetStatus(result.statusMessage || 'Click in model to place the origin helper point.'); return; }
        if (result.isSaved) {
            na_state.isValidated = false; na_state.validationResult = null;
            Na__Render();
            Na__SetStatus(result.statusMessage || 'Profile saved successfully.');
        } else {
            Na__SetStatus(result.statusMessage || 'Profile save failed.');
        }
    }

    // endregion ----------------------------------------------------------------

    // -------------------------------------------------------------------------
    // REGION | Exports
    // -------------------------------------------------------------------------

    window.Na__ProfileTools__CreateNewProfile__Tab         = { na_mount: na_mount, na_unmount: na_unmount };
    window.Na__ProfilePathTracer__ReceiveExportValidation  = Na__ReceiveExportValidation;
    window.Na__ProfilePathTracer__ReceiveSaveProfileResult = Na__ReceiveSaveProfileResult;

    // endregion ----------------------------------------------------------------

})();