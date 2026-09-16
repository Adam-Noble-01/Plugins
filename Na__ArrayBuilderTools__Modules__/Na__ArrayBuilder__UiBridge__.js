/* =============================================================================
   NA ARRAY BUILDER TOOLS - UI BRIDGE
   FILE       : Na__ArrayBuilder__UiBridge__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Tab routing, debounced live controls and saved preset workflows.
   ============================================================================= */

import { Na__UiInput__ParseLength } from './Na__ArrayBuilder__UiInput__.js';
import { Na__Parameters__Install, Na__Parameters__Sync, Na__Parameters__Commit } from './Na__ArrayBuilder__UiParameters__.js';
import { Na__Preview__Markup, Na__Preview__Sample } from './Na__ArrayBuilder__UiPreview__.js';

// REGION | Session State -----------------------------------------------------
let na_state = { context: null, config: {}, editing: false, placing: false, live: true, can_edit: false };
let na_tab = 'create';
let na_pending = null;
let na_presets = [];
let na_preset_id = null;
const na_fields = [...document.querySelectorAll('[data-na-field]')];
const Na__Ui__Element = na_id => document.getElementById(na_id);

function Na__Ui__Send(na_action, na_extra = {}) {
    if (!window.sketchup?.na_arrayAction) return;
    window.sketchup.na_arrayAction(JSON.stringify({ action: na_action, context: na_state.context, ...na_extra }));
}

function Na__Ui__Status(na_type, na_message) {
    Na__Ui__Element('na-status').textContent = na_message;
    document.querySelector('.na-status-bar').dataset.naLevel = na_type;
}

function Na__Ui__CancelPending() {
    clearTimeout(na_pending);
    na_pending = null;
}

function Na__Ui__ReadConfig(na_mark = true) {
    const na_config = { ...na_state.config };
    let na_valid = true;
    na_fields.forEach(na_field => {
        const na_key = na_field.dataset.naField;
        if (na_field.type === 'checkbox') na_config[na_key] = na_field.checked;
        else if (na_field.tagName === 'SELECT') na_config[na_key] = na_field.value;
        else {
            const na_value = na_field.dataset.naExpressionPending ? null : Na__UiInput__ParseLength(na_field.value, na_key);
            const na_relevant = !(na_config.type === 'object' && na_key.startsWith('unit_')) &&
                !(na_key === 'inset_mm' && na_config.distribution !== 'inset');
            if (na_value === null && na_relevant) na_valid = false;
            if (na_mark) na_field.setAttribute('aria-invalid', String(na_value === null && na_relevant));
            if (na_value !== null) na_config[na_key] = na_value;
        }
    });
    if (!na_valid) return null;
    return na_config;
}

function Na__Ui__Configure() {
    Na__Ui__CancelPending();
    const na_config = Na__Ui__ReadConfig();
    if (!na_config) {
        const na_error = na_fields.find(na_field => na_field.getAttribute('aria-invalid') === 'true' && na_field.validationMessage);
        Na__Ui__Status('warning', na_error ? na_error.validationMessage + ' Your previous preview is kept.' : 'Enter or leave the field to calculate. Incomplete values keep the previous preview.');
        return;
    }
    na_state.config = na_config;
    Na__Ui__RefreshControls();
    Na__Ui__Status('info', na_state.editing && !na_state.live ? 'Changes ready. Press Update array to apply them.' : 'Settings updated.');
    const na_context = na_state.context;
    na_pending = setTimeout(() => {
        na_pending = null;
        if (na_context !== na_state.context) return;
        Na__Ui__Send('configure', { config: na_config, scope: Na__Ui__Element('na-scope').value });
        if (!window.sketchup) Na__Ui__Element('na-preview').innerHTML = Na__Preview__Markup(Na__Preview__Sample(na_config));
    }, 180);
}

// REGION | Tabs and Shared Controls ------------------------------------------
function Na__Ui__Tab(na_next) {
    if (!['create', 'edit', 'gallery', 'preset', 'settings'].includes(na_next)) return;
    Na__Ui__CancelPending();
    if ((na_next === 'create' || na_next === 'preset') && na_state.editing) Na__Ui__Send('new', { config: Na__Ui__ReadConfig() || na_state.config });
    na_tab = na_next;
    document.querySelectorAll('[data-na-tab]').forEach(na_button => {
        const na_active = na_button.dataset.naTab === na_tab;
        na_button.classList.toggle('na-tab-active', na_active);
        na_button.setAttribute('aria-selected', String(na_active));
        na_button.tabIndex = na_active ? 0 : -1;
        Na__Ui__Element('na-panel-' + na_button.dataset.naTab).hidden = !na_active;
    });
    const na_editor = Na__Ui__Element('na-editor');
    const na_mount = na_tab === 'edit' ? 'na-edit-editor' : na_tab === 'preset' ? 'na-preset-editor' : 'na-create-editor';
    Na__Ui__Element(na_mount).appendChild(na_editor);
    na_editor.hidden = !['create', 'preset'].includes(na_tab) && !(na_tab === 'edit' && na_state.editing);
    Na__Ui__RefreshControls();
}

function Na__Ui__WriteConfig() {
    na_fields.forEach(na_field => {
        const na_value = na_state.config[na_field.dataset.naField];
        if (na_value === undefined) return;
        if (na_field.type === 'checkbox') na_field.checked = na_value === true;
        else na_field.value = typeof na_value === 'number' ? Number(na_value.toFixed(3)) : na_value;
        na_field.removeAttribute('aria-invalid');
        Na__Parameters__Sync(na_field, true);
    });
    Na__Ui__RefreshControls();
}

function Na__Ui__RefreshControls() {
    const na_object = na_state.config.type === 'object';
    Na__Ui__Element('na-block-fields').hidden = na_object;
    Na__Ui__Element('na-merge-field').hidden = na_object;
    Na__Ui__Element('na-object-fields').hidden = !na_object;
    Na__Ui__Element('na-inset-field').hidden = na_state.config.distribution !== 'inset';
    document.querySelectorAll('[data-na-type]').forEach(na_button => {
        const na_active = na_button.dataset.naType === na_state.config.type;
        na_button.classList.toggle('na-choice-active', na_active);
        na_button.setAttribute('aria-pressed', String(na_active));
    });
    const na_distribution_text = {
        fixed: 'A constant face-to-face gap along the entire path.',
        normalise: 'Fits units to each segment and adjusts the gap to the nearest clean fit.',
        inset: 'Equal margins at each segment end. Negative values extend the units outwards.'
    };
    Na__Ui__Element('na-distribution-help').textContent = na_distribution_text[na_state.config.distribution] || '';
    Na__Ui__Element('na-edit-empty').hidden = na_state.editing;
    Na__Ui__Element('na-editor').hidden = !['create', 'preset'].includes(na_tab) && !(na_tab === 'edit' && na_state.editing);
    Na__Ui__Element('na-path-section').hidden = na_tab === 'preset';
    Na__Ui__Element('na-path-source-row').hidden = na_state.editing;
    Na__Ui__Element('na-scope-row').hidden = !na_state.editing;
    Na__Ui__Element('na-edit-help').hidden = !na_state.editing;
    Na__Ui__Element('na-redraw').hidden = !na_state.editing || na_state.placing;
    Na__Ui__Element('na-stop').hidden = !na_state.placing;
    Na__Ui__Element('na-primary').textContent = na_state.placing ? 'Finish path / build array' : na_state.editing ? 'Update array' :
        na_state.config.path_source === 'selection' ? 'Preview selected path' : 'Draw array path';
    Na__Ui__Element('na-primary').dataset.naAction = na_state.placing ? 'finish' : na_state.editing ? 'update' : 'start';
    document.querySelectorAll('[data-na-edit-button]').forEach(na_button => { na_button.disabled = !na_state.can_edit || na_state.placing; });
    Na__Ui__Element('na-live').checked = na_state.live;
}

// REGION | Preset Gallery and Editor -----------------------------------------
function Na__Ui__NewPreset() {
    na_preset_id = null;
    Na__Ui__Element('na-preset-name').value = '';
    Na__Ui__Element('na-preset-category').value = '';
    Na__Ui__Element('na-preset-description').value = '';
    Na__Ui__Element('na-preset-state').textContent = 'New preset';
    Na__Ui__Element('na-archive').disabled = true;
    Na__Ui__Tab('preset');
}

function Na__Ui__PresetDetails(na_record) {
    na_preset_id = na_record.id;
    Na__Ui__Element('na-preset-name').value = na_record.name;
    Na__Ui__Element('na-preset-category').value = na_record.category;
    Na__Ui__Element('na-preset-description').value = na_record.description;
    Na__Ui__Element('na-preset-state').textContent = 'Saved preset';
    Na__Ui__Element('na-archive').disabled = false;
}

function Na__Ui__Node(na_tag, na_class, na_text) {
    const na_node = document.createElement(na_tag);
    if (na_class) na_node.className = na_class;
    if (na_text !== undefined) na_node.textContent = na_text;
    return na_node;
}

function Na__Ui__Gallery() {
    const na_gallery = Na__Ui__Element('na-gallery');
    na_gallery.replaceChildren();
    const na_search = Na__Ui__Element('na-search').value.toLowerCase();
    const na_filter = Na__Ui__Element('na-gallery-filter').value;
    const na_records = na_presets.filter(na_record => (na_filter === 'all' || na_record.configuration.type === na_filter) &&
        [na_record.name, na_record.category, na_record.description].join(' ').toLowerCase().includes(na_search));
    if (!na_records.length) {
        const na_empty = Na__Ui__Node('div', 'na-empty-state');
        na_empty.append(Na__Ui__Node('div', 'na-empty-symbol', '▥'), Na__Ui__Node('h2', '', na_presets.length ? 'No matching presets' : 'Your array library starts here'));
        na_empty.append(Na__Ui__Node('p', '', na_presets.length ? 'Try another search or source filter.' : 'Set up an array, then save its settings to build your own collection.'));
        if (!na_presets.length) {
            const na_button = Na__Ui__Node('button', 'na-btn', 'Save your first preset');
            na_button.addEventListener('click', Na__Ui__NewPreset);
            na_empty.append(na_button);
        }
        na_gallery.append(na_empty);
        return;
    }
    na_records.forEach(na_record => {
        const na_card = Na__Ui__Node('article', 'na-preset-card');
        const na_preview = Na__Ui__Node('div', 'na-preset-card__preview');
        na_preview.innerHTML = Na__Preview__Markup(Na__Preview__Sample(na_record.configuration));
        const na_body = Na__Ui__Node('div', 'na-preset-card__body');
        na_body.append(Na__Ui__Node('div', 'na-preset-category', na_record.category || 'My arrays'), Na__Ui__Node('h2', '', na_record.name));
        na_body.append(Na__Ui__Node('p', '', na_record.description || (na_record.configuration.type === 'object' ? 'Custom object array' : 'Parametric block array')));
        na_body.append(Na__Ui__Node('p', '', na_record.configuration.spacing_mm + ' mm target gap · ' + na_record.configuration.distribution));
        const na_buttons = Na__Ui__Node('div', 'na-button-row');
        [['Use preset', 'preset_load'], ['Edit preset', 'preset_edit']].forEach(([na_label, na_action]) => {
            const na_button = Na__Ui__Node('button', 'na-btn' + (na_action === 'preset_edit' ? ' na-btn-secondary' : ''), na_label);
            na_button.addEventListener('click', () => { Na__Ui__CancelPending(); Na__Ui__Send(na_action, { id: na_record.id }); });
            na_buttons.append(na_button);
        });
        na_body.append(na_buttons);
        na_card.append(na_preview, na_body);
        na_gallery.append(na_card);
    });
}

// REGION | User Actions ------------------------------------------------------
function Na__Ui__Action(na_action) {
    Na__Ui__CancelPending();
    na_fields.forEach(na_field => Na__Parameters__Commit(na_field));
    if (na_action === 'preset_new') { Na__Ui__NewPreset(); return; }
    const na_config = Na__Ui__ReadConfig();
    if (['start','redraw','update','finish','preset_save','preset_copy','reload'].includes(na_action) && !na_config) {
        Na__Ui__Status('warning', 'Complete the highlighted dimensions before continuing.');
        return;
    }
    if (na_action === 'preset_save' || na_action === 'preset_copy') {
        const na_name = Na__Ui__Element('na-preset-name').value.trim();
        if (!na_name) { Na__Ui__Element('na-preset-name').focus(); Na__Ui__Status('warning', 'Give this preset a name.'); return; }
        Na__Ui__Send('preset_save', { config: na_config, id: na_action === 'preset_copy' ? null : na_preset_id,
            name: na_name, category: Na__Ui__Element('na-preset-category').value, description: Na__Ui__Element('na-preset-description').value });
        return;
    }
    if (na_action === 'preset_archive') {
        if (na_preset_id) Na__Ui__Send('preset_archive', { id: na_preset_id });
        Na__Ui__NewPreset();
        Na__Ui__Tab('gallery');
        return;
    }
    if (na_action === 'redraw' && na_config) na_config.path_source = 'draw';
    // Finish must apply the latest keystroke before the SketchUp tool commits.
    if (na_action === 'finish') Na__Ui__Send('configure', { config: na_config, scope: Na__Ui__Element('na-scope').value });
    Na__Ui__Send(na_action, { config: na_config, scope: Na__Ui__Element('na-scope').value });
}

// REGION | Ruby to JavaScript ------------------------------------------------
window.Na__ArrayUi__Receive = function Na__ArrayUi__Receive(na_event, na_payload) {
    if (na_event === 'state') {
        const na_changed = na_state.context !== na_payload.context;
        if (na_changed) Na__Ui__CancelPending();
        const na_config = na_changed ? na_payload.config : na_state.config;
        na_state = { ...na_state, ...na_payload, config: na_config };
        if (na_changed) {
            Na__Ui__WriteConfig();
            Na__Ui__Element('na-scope').value = na_state.scope || 'single';
        }
        Na__Ui__Element('na-source-name').textContent = na_state.source_name || 'No source selected';
        Na__Ui__Element('na-source-size').textContent = na_state.source_dimensions ? na_state.source_dimensions.join(' × ') + ' mm · width / depth / height' : 'Pick a group or component from the model.';
        Na__Ui__Element('na-edit-title').textContent = na_state.editing ? (na_state.target_name || 'Noble Array') + ' · ' + na_state.linked_count + ' linked instance(s)' : 'Select a Noble array to load its saved settings.';
        Na__Ui__RefreshControls();
    } else if (na_event === 'status') Na__Ui__Status(na_payload.type, na_payload.message);
    else if (na_event === 'tab') Na__Ui__Tab(na_payload);
    else if (na_event === 'placing') { na_state.placing = na_payload; Na__Ui__RefreshControls(); }
    else if (na_event === 'reverse') {
        na_state.config.reverse_path = na_payload;
        document.querySelector('[data-na-field="reverse_path"]').checked = na_payload;
    } else if (na_event === 'completed') {
        na_state.placing = false;
        Na__Ui__RefreshControls();
        Na__Ui__Status('success', 'Array created. Select it and use Edit selected array to keep adjusting it.');
    } else if (na_event === 'updated') {
        na_state.linked_count = na_payload.linked_count;
        Na__Ui__Element('na-edit-title').textContent = (na_state.target_name || 'Noble Array') + ' · ' + na_state.linked_count + ' linked instance(s)';
    } else if (na_event === 'metrics') {
        const Na__Ui__Number = na_value => Number.isFinite(na_value) ? Number(na_value.toFixed(1)).toLocaleString() : '—';
        Na__Ui__Element('na-count').textContent = Na__Ui__Number(na_payload.count);
        Na__Ui__Element('na-length').textContent = Na__Ui__Number(na_payload.length_mm);
        Na__Ui__Element('na-gap').textContent = Na__Ui__Number(na_payload.gap_mm);
        if (na_state.placing) Na__Ui__Element('na-preview-caption').textContent = 'Live SketchUp path';
    } else if (na_event === 'preview') {
        const na_preview = Na__Ui__Element('na-preview');
        if (na_payload.missing_source || na_payload.error) na_preview.textContent = na_payload.error || 'Pick a source object to preview this array.';
        else na_preview.innerHTML = Na__Preview__Markup(na_payload);
        Na__Ui__Element('na-preview-caption').textContent = (na_payload.sample ? '3,000 mm sample path' : na_payload.placing ? 'Live SketchUp path' : 'Saved array path') + (na_payload.truncated ? ' · ' + na_payload.preview_count + ' units shown for performance' : ' · actual geometry');
    } else if (na_event === 'gallery') {
        na_presets = na_payload.records;
        const na_warning = Na__Ui__Element('na-gallery-warning');
        na_warning.hidden = !na_payload.skipped.length;
        na_warning.textContent = na_payload.skipped.length + ' unreadable preset file(s) skipped. Check the library folder.';
        Na__Ui__Gallery();
    } else if (na_event === 'preset_saved') Na__Ui__PresetDetails(na_payload);
    else if (na_event === 'preset_edit') { Na__Ui__PresetDetails(na_payload); Na__Ui__Tab('preset'); }
    else if (na_event === 'preset_loaded') { Na__Ui__Tab('create'); Na__Ui__Status('success', 'Loaded ' + na_payload.name + '. Choose or draw a path.'); }
};

// REGION | Bootstrap ---------------------------------------------------------
document.querySelectorAll('[data-na-tab]').forEach(na_button => {
    na_button.addEventListener('click', () => Na__Ui__Tab(na_button.dataset.naTab));
    na_button.addEventListener('keydown', na_event => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(na_event.key)) return;
        const na_tabs = [...document.querySelectorAll('[data-na-tab]')];
        const na_index = na_tabs.indexOf(na_button);
        const na_next = na_event.key === 'Home' ? 0 : na_event.key === 'End' ? na_tabs.length - 1 : (na_index + (na_event.key === 'ArrowRight' ? 1 : -1) + na_tabs.length) % na_tabs.length;
        na_event.preventDefault();
        Na__Ui__Tab(na_tabs[na_next].dataset.naTab);
        na_tabs[na_next].focus();
    });
});
document.querySelectorAll('[data-na-action]').forEach(na_button => na_button.addEventListener('click', () => Na__Ui__Action(na_button.dataset.naAction)));
document.querySelectorAll('[data-na-type]').forEach(na_button => na_button.addEventListener('click', () => {
    na_state.config.type = na_button.dataset.naType;
    Na__Ui__Configure();
}));
Na__Parameters__Install(na_fields, Na__Ui__Configure);
na_fields.filter(na_field => !na_field.dataset.naParameter).forEach(na_field => {
    na_field.addEventListener('input', Na__Ui__Configure);
});
Na__Ui__Element('na-live').addEventListener('change', na_event => { Na__Ui__CancelPending(); Na__Ui__Send('live', { enabled: na_event.target.checked }); });
Na__Ui__Element('na-scope').addEventListener('change', () => {
    Na__Ui__CancelPending();
    Na__Ui__Status('info', 'Update scope changed. The next parameter change or Update array applies to this scope.');
});
Na__Ui__Element('na-search').addEventListener('input', Na__Ui__Gallery);
Na__Ui__Element('na-gallery-filter').addEventListener('change', Na__Ui__Gallery);
na_state.config = { type: 'block', ...Na__Ui__ReadConfig(false) };
Na__Ui__Tab('create');
Na__Ui__Gallery();
Na__Ui__Send('ready');
if (!window.sketchup) {
    Na__Ui__Element('na-preview').innerHTML = Na__Preview__Markup(Na__Preview__Sample(na_state.config));
    Na__Ui__Status('info', 'Interface preview · open Array Builder in SketchUp to create and edit geometry.');
} else Na__Ui__Status('info', 'Ready. Draw a path, use selected edges, or open an existing array.');
