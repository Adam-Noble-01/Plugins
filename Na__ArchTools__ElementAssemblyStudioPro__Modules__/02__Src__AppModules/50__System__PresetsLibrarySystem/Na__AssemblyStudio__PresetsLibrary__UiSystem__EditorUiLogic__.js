// =============================================================================
// ELEMENT ASSEMBLY STUDIO PRO - PRESETS LIBRARY - PRESET EDITOR TAB UI LOGIC
// =============================================================================
//
// FILE       : Na__AssemblyStudio__PresetsLibrary__UiSystem__EditorUiLogic__.js
// NAMESPACE  : window.Na_PresetEditorUI
// MODULE     : Preset Editor Tab
// AUTHOR     : Noble Architecture
// PURPOSE    : Owns the Preset Editor tab: CREATE mode (metadata form for a
//              freshly captured design) and EDIT mode (metadata / config
//              overwrite for existing presets).
//              Implements the Na_TabRouter mount/unmount contract.
// CREATED    : 2026
//
// DESCRIPTION:
// - Renders into #na-preset-editor-body on na_mount(); unmount wipes it.
// - CREATE mode consumes the Bridge's pending capture: SVG preview panel,
//   readonly code/family/type/timestamp rows, editable name/description/
//   keywords, Save New Preset + Cancel actions.
// - EDIT mode lists all presets in an optgroup selector (grouped by
//   family, ordered by code); Save Changes patches metadata, Update From
//   Current UI overwrites config + preview behind a two-click arm confirm
//   (no window.confirm), Back to Gallery returns to the gallery tab.
// - Save results and library pushes arrive via the Bridge dispatch hooks
//   na_on_save_result(payload) / na_on_library_updated().
//
// NAMING CONVENTION:
// - Aggregate Na_PresetEditorUI + na_* internal helpers.
//
// =============================================================================


(function () {
    'use strict';


// -----------------------------------------------------------------------------
// REGION | Module State & Constants
// -----------------------------------------------------------------------------

    var Na_PresetEditorUI             = {};

    var NA_BODY_ID                    = 'na-preset-editor-body';              // <-- Host body div inside #na-tab-preset_editor
    var NA_ARM_TIMEOUT_MS             = 4000;                                 // <-- Two-click confirm window for config overwrite
    var NA_UPDATE_BTN_LABEL           = 'Update From Current UI';
    var NA_UPDATE_BTN_ARMED_LABEL     = 'Click again to confirm overwrite';
    var NA_SVG_NAMESPACE              = 'http://www.w3.org/2000/svg';

    var NA_FAMILY_GROUPS              = [
        { family : 'Window',       label : 'Windows'        },
        { family : 'ExteriorDoor', label : 'Exterior Doors' },
        { family : 'InteriorDoor', label : 'Interior Doors' }
    ];

    var na_is_mounted                 = false;                                // <-- True between na_mount and na_unmount
    var na_mode                       = 'edit';                               // <-- 'create' | 'edit'
    var na_selected_code              = '';                                   // <-- Preset pre-selected for EDIT mode
    var na_is_saving                  = false;                                // <-- True while a save round-trip is pending
    var na_update_arm_timer           = null;                                 // <-- Non-null while the overwrite confirm is armed

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Generic Helpers
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Return the Editor Body Host Element
    // ------------------------------------------------------------
    // @return {Element|null} #na-preset-editor-body when present
    function na_body() {
        return document.getElementById(NA_BODY_ID);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Return the Presets Bridge (Guarded)
    // ------------------------------------------------------------
    // @return {Object|null} window.Na__PresetsLibrary__Bridge when loaded
    function na_bridge() {
        return (typeof window.Na__PresetsLibrary__Bridge !== 'undefined')
            ? window.Na__PresetsLibrary__Bridge
            : null;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Show a Status-Bar Message (Guarded)
    // ------------------------------------------------------------
    // @param {String} type    - 'success' | 'error' | 'warning' | 'info'
    // @param {String} message - Message to display
    function na_status(type, message) {
        if (typeof window.na_showStatus !== 'function') return;
        try { window.na_showStatus(type, message); }
        catch (err) { console.warn('[NA_PRESET_EDITOR] na_showStatus failed:', err); }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Activate Another Tab Through the Router (Guarded)
    // ------------------------------------------------------------
    // @param {String} tabId - Router tab id to activate
    function na_activate_tab(tabId) {
        if (window.Na_TabRouter && typeof window.Na_TabRouter.na_activateTab === 'function') {
            window.Na_TabRouter.na_activateTab(tabId);
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Escape Text Interpolated Into Markup Strings
    // ------------------------------------------------------------
    // @param  {String} str - Raw text
    // @return {String}       HTML-safe text
    function na_escape_html(str) {
        return String(str || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Parse a Comma-Separated Keywords String
    // ------------------------------------------------------------
    // @param  {String} raw - e.g. 'casement, cottage'
    // @return {Array}        Trimmed non-empty keyword strings
    function na_parse_keywords(raw) {
        return String(raw || '')
            .split(',')
            .map(function (keyword) { return keyword.trim(); })
            .filter(function (keyword) { return keyword.length > 0; });
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Builders - Form Rows, Preview & Actions
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | One Labelled Form Row Wrapping a Field Element
    // ------------------------------------------------------------
    // @param  {String}  labelText - Row label copy
    // @param  {Element} fieldEl   - Input / textarea / select element
    // @return {Element}             div.na-preset-editor__row
    function na_build_row(labelText, fieldEl) {
        var row = document.createElement('div');
        row.className = 'na-preset-editor__row';

        var label = document.createElement('label');
        label.className   = 'na-preset-editor__label';
        label.textContent = labelText;
        if (fieldEl && fieldEl.id) label.htmlFor = fieldEl.id;

        row.appendChild(label);
        row.appendChild(fieldEl);
        return row;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | One Text Input (Editable or Readonly)
    // ------------------------------------------------------------
    // @param  {String}  id          - Element id ('' for none)
    // @param  {String}  value       - Initial value
    // @param  {Boolean} isReadonly  - True for readonly display rows
    // @param  {String}  placeholder - Placeholder copy for editable rows
    // @return {Element}               input.na-preset-editor__input
    function na_build_text_input(id, value, isReadonly, placeholder) {
        var input = document.createElement('input');
        input.type      = 'text';
        input.className = 'na-preset-editor__input';
        if (id) input.id = id;
        input.value = String(value || '');
        if (placeholder) input.placeholder = placeholder;
        if (isReadonly) {
            input.readOnly = true;
            input.className += ' na-preset-editor__input--readonly';
            input.title = String(value || '');
        }
        return input;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Description Textarea
    // ------------------------------------------------------------
    // @param  {String} value - Initial value
    // @return {Element}        textarea.na-preset-editor__textarea
    function na_build_textarea(value) {
        var textarea = document.createElement('textarea');
        textarea.id          = 'na-preset-editor-description';
        textarea.className   = 'na-preset-editor__textarea';
        textarea.rows        = 2;
        textarea.placeholder = 'Brief description';
        textarea.value       = String(value || '');
        return textarea;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Stored / Captured SVG Preview Panel
    // ------------------------------------------------------------
    // Rebuilds a detached <svg> from the stored viewBox + inner markup
    // (CardRenderer pattern). Falls back to a note when no preview exists.
    // @param  {Object} svgPreview - { viewBox, widthMm, heightMm, svgMarkup }
    // @param  {String} designName - Name used in the fallback note
    // @return {Element}             div.na-preset-editor__preview
    function na_build_preview(svgPreview, designName) {
        var preview = document.createElement('div');
        preview.className = 'na-preset-editor__preview';

        var markup = svgPreview && svgPreview.svgMarkup ? String(svgPreview.svgMarkup) : '';
        if (!markup) {
            preview.innerHTML = '<p>No stored preview for ' + na_escape_html(designName || 'this preset') + '.</p>';
            return preview;
        }

        var svg = document.createElementNS(NA_SVG_NAMESPACE, 'svg');
        svg.setAttribute('viewBox', String(svgPreview.viewBox || '0 0 100 100'));
        svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
        svg.innerHTML = markup;
        preview.appendChild(svg);
        return preview;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | One Action Button
    // ------------------------------------------------------------
    // @param  {String}   id        - Element id
    // @param  {String}   label     - Button copy
    // @param  {String}   className - Full button class list
    // @param  {Function} onClick   - Click handler
    // @return {Element}              button element
    function na_build_action_button(id, label, className, onClick) {
        var button = document.createElement('button');
        button.id          = id;
        button.type        = 'button';
        button.className   = className;
        button.textContent = label;
        button.addEventListener('click', onClick);
        return button;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Editor Empty-State Block
    // ------------------------------------------------------------
    // @param  {Array} messageLines - Paragraph copy lines
    // @return {Element}              div.na-preset-editor__empty
    function na_build_empty_state(messageLines) {
        var empty = document.createElement('div');
        empty.className = 'na-preset-editor__empty';

        messageLines.forEach(function (line) {
            var p = document.createElement('p');
            p.textContent = line;
            empty.appendChild(p);
        });

        empty.appendChild(na_build_action_button(
            'na-preset-editor-go-gallery',
            'Go to Gallery',
            'na-btn na-btn-secondary',
            function () { na_activate_tab('presets'); }
        ));
        return empty;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | CREATE Mode - Metadata Form for a Fresh Capture
// -----------------------------------------------------------------------------

    // FUNCTION | Render the CREATE-Mode Form Into the Body Host
    // ------------------------------------------------------------
    // Consumes the Bridge's pending capture; when none is stashed the
    // editor falls back to an explanatory empty state.
    // @param {Element} body - The wiped #na-preset-editor-body host
    function na_render_create_mode(body) {
        var bridge  = na_bridge();
        var pending = (bridge && typeof bridge.na_get_pending_capture === 'function')
            ? bridge.na_get_pending_capture()
            : null;

        if (!pending) {
            body.appendChild(na_build_empty_state([
                'No captured design on file.',
                'Use Capture Current Design in the gallery to start a new preset.'
            ]));
            return;
        }

        var root = document.createElement('div');
        root.className = 'na-preset-editor';
        root.appendChild(na_build_preview(pending.svgPreview, 'the captured design'));

        var form = document.createElement('div');
        form.className = 'na-preset-editor__form';
        form.appendChild(na_build_row('Preset Code',
            na_build_text_input('na-preset-editor-code', 'EAS0XX — assigned on save', true, '')));
        form.appendChild(na_build_row('Product Family',
            na_build_text_input('', pending.productFamily, true, '')));
        form.appendChild(na_build_row('Product Type',
            na_build_text_input('', pending.productType, true, '')));
        form.appendChild(na_build_row('Captured',
            na_build_text_input('', pending.capturedAt, true, '')));
        form.appendChild(na_build_row('Preset Name',
            na_build_text_input('na-preset-editor-name', '', false, 'Preset name')));
        form.appendChild(na_build_row('Description', na_build_textarea('')));
        form.appendChild(na_build_row('Keywords',
            na_build_text_input('na-preset-editor-keywords', '', false, 'keyword1, keyword2, ...')));
        root.appendChild(form);

        var actions = document.createElement('div');
        actions.className = 'na-preset-editor__actions';
        actions.appendChild(na_build_action_button(
            'na-preset-editor-save-new',
            'Save New Preset',
            'na-btn na-btn-success',
            na_on_save_new_clicked
        ));
        actions.appendChild(na_build_action_button(
            'na-preset-editor-cancel',
            'Cancel',
            'na-btn na-btn-secondary',
            function () {
                na_mode = 'edit';
                na_activate_tab('presets');
            }
        ));
        root.appendChild(actions);

        body.appendChild(root);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Validate the CREATE Form and Dispatch the Save
    // ------------------------------------------------------------
    function na_on_save_new_clicked() {
        if (na_is_saving) return;

        var bridge = na_bridge();
        if (!bridge || typeof bridge.na_save_new_preset !== 'function') {
            na_status('error', 'Presets bridge unavailable - cannot save preset.');
            return;
        }

        var nameEl = document.getElementById('na-preset-editor-name');
        var descEl = document.getElementById('na-preset-editor-description');
        var kwEl   = document.getElementById('na-preset-editor-keywords');

        var presetName = nameEl ? nameEl.value.trim() : '';
        if (!presetName) {
            na_status('warning', 'Preset Name is required before saving.');
            return;
        }

        var wasSent = bridge.na_save_new_preset({
            presetName        : presetName,
            presetDescription : descEl ? descEl.value.trim() : '',
            presetKeywords    : na_parse_keywords(kwEl ? kwEl.value : '')
        });
        if (!wasSent) return;

        na_is_saving = true;
        var saveBtn  = document.getElementById('na-preset-editor-save-new');
        if (saveBtn) {
            saveBtn.disabled    = true;
            saveBtn.textContent = 'Saving...';
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | EDIT Mode - Preset Selector, Metadata Patch & Config Overwrite
// -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve the Record Shown by the EDIT Form
    // ------------------------------------------------------------
    // @param  {Array} records - Cached preset records
    // @return {Object|null}     Pre-selected record, else the first record
    function na_resolve_selected_record(records) {
        if (!records.length) return null;
        for (var i = 0; i < records.length; i++) {
            if (records[i] && records[i].presetCode === na_selected_code) return records[i];
        }
        return records[0];
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | The Family-Grouped Preset Selector
    // ------------------------------------------------------------
    // Known families render in fixed order (Windows, Exterior Doors,
    // Interior Doors); any unexpected family gets its own trailing group.
    // Options within each group are ordered by preset code.
    // @param  {Array}  records      - Cached preset records
    // @param  {String} selectedCode - Code to pre-select
    // @return {Element}               select#na-preset-editor-select
    function na_build_preset_selector(records, selectedCode) {
        var select = document.createElement('select');
        select.id        = 'na-preset-editor-select';
        select.className = 'na-preset-editor__input';

        var grouped = {};
        records.forEach(function (record) {
            if (!record) return;
            var family = record.productFamily || 'Other';
            if (!grouped[family]) grouped[family] = [];
            grouped[family].push(record);
        });

        var familyOrder  = [];
        NA_FAMILY_GROUPS.forEach(function (group) {
            if (grouped[group.family]) familyOrder.push({ family: group.family, label: group.label });
        });
        Object.keys(grouped).sort().forEach(function (family) {
            var isKnown = NA_FAMILY_GROUPS.some(function (group) { return group.family === family; });
            if (!isKnown) familyOrder.push({ family: family, label: family });
        });

        familyOrder.forEach(function (group) {
            var optgroup = document.createElement('optgroup');
            optgroup.label = group.label;

            grouped[group.family]
                .slice()
                .sort(function (a, b) {
                    return String(a.presetCode || '').localeCompare(String(b.presetCode || ''));
                })
                .forEach(function (record) {
                    var option = document.createElement('option');
                    option.value       = record.presetCode || '';
                    option.textContent = String(record.presetCode || '') + ' — ' + String(record.displayName || '');
                    option.selected    = (record.presetCode === selectedCode);
                    optgroup.appendChild(option);
                });

            select.appendChild(optgroup);
        });

        select.addEventListener('change', function () {
            na_selected_code = select.value;
            na_disarm_update_button();
            na_render();
        });
        return select;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Render the EDIT-Mode Form Into the Body Host
    // ------------------------------------------------------------
    // @param {Element} body - The wiped #na-preset-editor-body host
    function na_render_edit_mode(body) {
        var bridge  = na_bridge();
        var records = (bridge && typeof bridge.na_get_presets === 'function')
            ? bridge.na_get_presets()
            : [];

        if (!records.length) {
            body.appendChild(na_build_empty_state([
                'No presets saved yet.',
                'Use Capture Current Design in the gallery to save your first preset.'
            ]));
            return;
        }

        var record = na_resolve_selected_record(records);
        if (!record) return;
        na_selected_code = record.presetCode || '';

        var root = document.createElement('div');
        root.className = 'na-preset-editor';
        root.appendChild(na_build_preview(record.svgPreview, record.displayName));

        var form = document.createElement('div');
        form.className = 'na-preset-editor__form';
        form.appendChild(na_build_row('Preset', na_build_preset_selector(records, na_selected_code)));
        form.appendChild(na_build_row('Preset Code',
            na_build_text_input('na-preset-editor-code', record.presetCode, true, '')));
        form.appendChild(na_build_row('Source File',
            na_build_text_input('na-preset-editor-source-file', record.sourceFile, true, '')));
        form.appendChild(na_build_row('Product Family',
            na_build_text_input('', record.productFamily, true, '')));
        form.appendChild(na_build_row('Product Type',
            na_build_text_input('', record.productType, true, '')));
        form.appendChild(na_build_row('Last Modified',
            na_build_text_input('', record.lastModified, true, '')));
        form.appendChild(na_build_row('Preset Name',
            na_build_text_input('na-preset-editor-name', record.displayName, false, 'Preset name')));
        form.appendChild(na_build_row('Description', na_build_textarea(record.description)));
        form.appendChild(na_build_row('Keywords',
            na_build_text_input('na-preset-editor-keywords',
                (record.keywords || []).join(', '), false, 'keyword1, keyword2, ...')));
        root.appendChild(form);

        var actions = document.createElement('div');
        actions.className = 'na-preset-editor__actions';
        actions.appendChild(na_build_action_button(
            'na-preset-editor-save-meta',
            'Save Changes',
            'na-btn na-btn-primary',
            function () { na_on_save_meta_clicked(record); }
        ));
        actions.appendChild(na_build_action_button(
            'na-preset-editor-update-config',
            NA_UPDATE_BTN_LABEL,
            'na-btn na-btn-secondary',
            function () { na_on_update_config_clicked(record); }
        ));
        actions.appendChild(na_build_action_button(
            'na-preset-editor-back',
            'Back to Gallery',
            'na-btn na-btn-secondary',
            function () { na_activate_tab('presets'); }
        ));
        root.appendChild(actions);

        body.appendChild(root);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Validate the EDIT Form and Dispatch the Metadata Patch
    // ------------------------------------------------------------
    // @param {Object} record - The preset record currently loaded
    function na_on_save_meta_clicked(record) {
        if (na_is_saving) return;

        var bridge = na_bridge();
        if (!bridge || typeof bridge.na_update_preset_meta !== 'function') {
            na_status('error', 'Presets bridge unavailable - cannot save changes.');
            return;
        }

        var nameEl = document.getElementById('na-preset-editor-name');
        var descEl = document.getElementById('na-preset-editor-description');
        var kwEl   = document.getElementById('na-preset-editor-keywords');

        var presetName = nameEl ? nameEl.value.trim() : '';
        if (!presetName) {
            na_status('warning', 'Preset Name is required before saving.');
            return;
        }

        var wasSent = bridge.na_update_preset_meta({
            presetCode        : record.presetCode,
            sourceFile        : record.sourceFile,
            presetName        : presetName,
            presetDescription : descEl ? descEl.value.trim() : '',
            presetKeywords    : na_parse_keywords(kwEl ? kwEl.value : '')
        });
        if (!wasSent) return;

        na_is_saving = true;
        var saveBtn  = document.getElementById('na-preset-editor-save-meta');
        if (saveBtn) {
            saveBtn.disabled    = true;
            saveBtn.textContent = 'Saving...';
        }
    }
    // ---------------------------------------------------------------

    // FUNCTION | Two-Click Arm Confirm for the Config Overwrite
    // ------------------------------------------------------------
    // First click arms the button (label swap + 4s disarm timer); the
    // second click within the window performs the overwrite. No
    // window.confirm is used anywhere in this flow.
    // @param {Object} record - The preset record currently loaded
    function na_on_update_config_clicked(record) {
        if (na_is_saving) return;

        var updateBtn = document.getElementById('na-preset-editor-update-config');
        if (!updateBtn) return;

        if (na_update_arm_timer === null) {
            updateBtn.textContent = NA_UPDATE_BTN_ARMED_LABEL;
            na_update_arm_timer   = setTimeout(na_disarm_update_button, NA_ARM_TIMEOUT_MS);
            return;
        }

        na_disarm_update_button();
        na_perform_config_overwrite(record, updateBtn);
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Re-Capture the Current UI and Dispatch the Overwrite
    // ------------------------------------------------------------
    // Capture origin follows the loaded preset's family: interior-door
    // presets re-capture from the Interior Doors UI, everything else from
    // the Windows tab UI. Family/type are re-derived from the fresh
    // capture so the stored preset always matches what was saved.
    // @param {Object}  record    - The preset record being overwritten
    // @param {Element} updateBtn - The overwrite button (for busy state)
    function na_perform_config_overwrite(record, updateBtn) {
        var bridge = na_bridge();
        if (!bridge ||
            typeof bridge.na_capture_current_design !== 'function' ||
            typeof bridge.na_update_preset_config !== 'function') {
            na_status('error', 'Presets bridge unavailable - cannot update preset.');
            return;
        }

        var origin  = (record.productFamily === 'InteriorDoor') ? 'doors' : 'windows';
        var capture = bridge.na_capture_current_design(origin);
        if (!capture) {
            na_status('error', 'Could not capture the current design - check the active configuration.');
            return;
        }

        var wasSent = bridge.na_update_preset_config({
            presetCode     : record.presetCode,
            sourceFile     : record.sourceFile,
            productFamily  : capture.productFamily,
            productType    : capture.productType,
            schemaContract : capture.schemaContract,
            configValues   : capture.configValues,
            svgPreview     : capture.svgPreview
        });

        if (typeof bridge.na_clear_pending_capture === 'function') {
            bridge.na_clear_pending_capture();                                // <-- Overwrite consumed the capture; keep create flow clean
        }
        if (!wasSent) return;

        na_is_saving          = true;
        updateBtn.disabled    = true;
        updateBtn.textContent = 'Saving...';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Disarm the Overwrite Confirm Button
    // ------------------------------------------------------------
    function na_disarm_update_button() {
        if (na_update_arm_timer !== null) {
            clearTimeout(na_update_arm_timer);
            na_update_arm_timer = null;
        }
        var updateBtn = document.getElementById('na-preset-editor-update-config');
        if (updateBtn && !na_is_saving) updateBtn.textContent = NA_UPDATE_BTN_LABEL;
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Rendering Orchestration
// -----------------------------------------------------------------------------

    // FUNCTION | Recompose the Entire Editor Body for the Active Mode
    // ------------------------------------------------------------
    function na_render() {
        var body = na_body();
        if (!body) return;

        body.innerHTML = '';
        if (na_mode === 'create') {
            na_render_create_mode(body);
        } else {
            na_render_edit_mode(body);
        }
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Restore Action Buttons After a Save Round-Trip
    // ------------------------------------------------------------
    function na_restore_action_buttons() {
        var saveNewBtn = document.getElementById('na-preset-editor-save-new');
        if (saveNewBtn) {
            saveNewBtn.disabled    = false;
            saveNewBtn.textContent = 'Save New Preset';
        }
        var saveMetaBtn = document.getElementById('na-preset-editor-save-meta');
        if (saveMetaBtn) {
            saveMetaBtn.disabled    = false;
            saveMetaBtn.textContent = 'Save Changes';
        }
        var updateBtn = document.getElementById('na-preset-editor-update-config');
        if (updateBtn) {
            updateBtn.disabled    = false;
            updateBtn.textContent = NA_UPDATE_BTN_LABEL;
        }
    }
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API - Bridge Hooks
// -----------------------------------------------------------------------------

    // FUNCTION | Handle a Save Result Pushed From Ruby via the Bridge
    // ------------------------------------------------------------
    // A successful CREATE save exits create mode, pre-selects the new
    // code and returns to the gallery; the library re-push arriving
    // separately re-renders every mounted presets tab.
    // @param {Object} payload - { isSaved, presetCode, sourceFile, statusMessage, reason }
    Na_PresetEditorUI.na_on_save_result = function (payload) {
        na_is_saving = false;
        na_restore_action_buttons();
        if (!payload) return;

        if (payload.isSaved) {
            na_status('success', payload.statusMessage || 'Preset saved.');
            if (na_mode === 'create') {
                var bridge = na_bridge();
                if (bridge && typeof bridge.na_clear_pending_capture === 'function') {
                    bridge.na_clear_pending_capture();
                }
                na_mode = 'edit';
                if (payload.presetCode) na_selected_code = payload.presetCode;
                na_activate_tab('presets');
            }
        } else {
            na_status('error', payload.statusMessage || 'Preset save failed.');
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Handle a Fresh Library Push From Ruby via the Bridge
    // ------------------------------------------------------------
    // EDIT mode re-renders against the new records; CREATE mode is left
    // alone so an in-progress metadata form is never stomped.
    Na_PresetEditorUI.na_on_library_updated = function () {
        if (!na_is_mounted) return;
        if (na_mode === 'edit') na_render();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Switch to CREATE Mode for the Pending Capture
    // ------------------------------------------------------------
    // Called by the gallery's capture flow just before it activates this
    // tab; re-renders immediately when the editor is already mounted.
    Na_PresetEditorUI.na_enter_create_mode = function () {
        na_mode      = 'create';
        na_is_saving = false;
        na_disarm_update_button();
        if (na_is_mounted) na_render();
    };
    // ---------------------------------------------------------------

    // FUNCTION | Pre-Select a Preset for the Next EDIT-Mode Render
    // ------------------------------------------------------------
    // Called by the gallery's per-card edit affordance before it
    // activates this tab.
    // @param {String} code - Preset code to pre-select
    Na_PresetEditorUI.na_set_selected_preset = function (code) {
        na_selected_code = String(code || '');
        na_mode          = 'edit';
        if (na_is_mounted) na_render();
    };
    // ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Public API - Mount Contract (shared HtmlDialog orchestrator)
// -----------------------------------------------------------------------------

    // FUNCTION | First Paint / Reopen Hook (config unused)
    // ------------------------------------------------------------
    Na_PresetEditorUI.na_mount = function (_initialConfig) {
        na_is_mounted = true;
        na_is_saving  = false;
        na_render();

        var bridge = na_bridge();
        if (bridge && typeof bridge.na_get_presets === 'function' &&
            !bridge.na_get_presets().length &&
            typeof bridge.na_request_library === 'function') {
            bridge.na_request_library();
        }
    };
    // ---------------------------------------------------------------

    // FUNCTION | Tab Tear-Down Clears Generated Nodes Only
    // ------------------------------------------------------------
    Na_PresetEditorUI.na_unmount = function () {
        na_is_mounted = false;
        na_disarm_update_button();
        var body = na_body();
        if (body) body.innerHTML = '';
    };
    // ---------------------------------------------------------------

    // FUNCTION | Editor Tab Emits No Persisted Config Payload
    // ------------------------------------------------------------
    Na_PresetEditorUI.na_get_active_config = function () {
        return null;
    };
    // ---------------------------------------------------------------

    window.Na_PresetEditorUI = Na_PresetEditorUI;

    console.log('[NA_PRESET_EDITOR] Preset Editor tab UiLogic mounted contract ready');

// endregion -------------------------------------------------------------------

})();
