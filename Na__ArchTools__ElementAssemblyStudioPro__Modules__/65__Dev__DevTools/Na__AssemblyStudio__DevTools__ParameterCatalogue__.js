/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - DEV TOOLS - PARAMETER CATALOGUE GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__ParameterCatalogue__.js
   AUTHOR     : Noble Architecture
   CREATED    : 11-Nov-2026 (V2.6.0)
   PURPOSE    : Writes 02__AppData/Na__AssemblyStudio__ParameterCatalogue__.json:
                every control the dialog shows, per system, with its label,
                unit, type, range, step, default, options, section and the
                plain-text condition it needs. The MCP seam
                (60__System__McpOperations) reads it to tell agents what each
                parameter means and to refuse values the dialog would never
                allow.

   HOW
   - The dialog's own files are run, unchanged, in a Node sandbox with a stub
     window and document: every *UiSystem__Config__.js (the descriptors) and
     every *UiSystem__LayoutMap__.js (the sections, captured through a stub
     Na__Ui__SectionLayout.na_register). So the catalogue is what the dialog uses,
     never a second copy typed by hand.
   - Generated descriptors are expanded: mullion offsets, glazing bar offsets,
     the arched header for windows and each door type; the per-casement
     overrides are described as a key pattern.
   - Functions (showIf, fixes) cannot be stored: a section item keeps its
     condition as text (need.text) only.

   RUN
     node Na__AssemblyStudio__DevTools__ParameterCatalogue__.js          write the JSON
     node Na__AssemblyStudio__DevTools__ParameterCatalogue__.js --check  exit 1 if it is stale

   NAMING CONVENTION:
   - All custom identifiers use Na__ or na_ prefix.
   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');
const vm   = require('vm');

const NA_SRC_ROOT  = path.resolve(__dirname, '..', '02__Src__AppModules');
const NA_OUT_FILE  = path.join(NA_SRC_ROOT, '02__AppData', 'Na__AssemblyStudio__ParameterCatalogue__.json');

// The window tab holds windows AND every exterior door type: one flat config.
const NA_SYSTEMS = {
    window_family: {
        tab: 'windows',
        configs: [
            '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js',
            '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
            '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js',
            '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__Config__.js',
            '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js'
        ],
        layout: '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__LayoutMap__.js'
    },
    interior_door: {
        tab: 'doors',
        configs: ['40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__UiSystem__Config__.js'],
        layout: '40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__UiSystem__LayoutMap__.js'
    },
    cabinet: {
        tab: 'cabinets',
        configs: ['45__System__InteriorCabinetry/Na__AssemblyStudio__Cabinetry__UiSystem__Config__.js'],
        layout: '45__System__InteriorCabinetry/Na__AssemblyStudio__Cabinetry__UiSystem__LayoutMap__.js'
    }
};

const NA_DESCRIPTOR_FIELDS = ['label', 'unit', 'type', 'min', 'max', 'step', 'default', 'options', 'materialsSource', 'placeholder', 'help', 'description'];

// =============================================================================
// REGION | Sandbox
// =============================================================================

function na_sandbox() {
    const noop = () => {};
    const element = new Proxy(function () {}, { get: (_t, key) => (key === 'style' || key === 'classList' || key === 'dataset' ? {} : noop) });
    const registered = {};
    const sandbox = {
        console: { log: noop, warn: noop, error: noop, info: noop, debug: noop },
        document: {
            getElementById: () => null, querySelector: () => null, querySelectorAll: () => [],
            createElement: () => element, addEventListener: noop, readyState: 'complete', body: element
        },
        setTimeout: noop, clearTimeout: noop, setInterval: noop, clearInterval: noop,
        Na__Ui__SectionLayout: { na_register: (tabId, spec) => { registered[tabId] = spec; } },
        __registered: registered
    };
    sandbox.window = sandbox;
    vm.createContext(sandbox);
    return sandbox;
}

function na_run(sandbox, relative) {
    const file = path.join(NA_SRC_ROOT, relative);
    vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox, { filename: file });
}

// =============================================================================
// REGION | Descriptors
// =============================================================================

function na_clean(value) {
    if (typeof value === 'function') return undefined;
    if (Array.isArray(value)) return value.map(na_clean).filter((item) => item !== undefined);
    if (value && typeof value === 'object') {
        const out = {};
        for (const [key, item] of Object.entries(value)) {
            const cleaned = na_clean(item);
            if (cleaned !== undefined) out[key] = cleaned;
        }
        return out;
    }
    return value;
}

// Flattens one descriptor array (with expandable children) into id -> record.
function na_collect(list, group, into, parent) {
    for (const descriptor of list || []) {
        if (!descriptor || typeof descriptor !== 'object') continue;
        const id = descriptor.id;
        if (id) {
            const record = { group: group };
            for (const field of NA_DESCRIPTOR_FIELDS) {
                if (descriptor[field] !== undefined) record[field] = na_clean(descriptor[field]);
            }
            if (parent) record.parent = parent;
            if (!into[id]) into[id] = record;
        }
        if (Array.isArray(descriptor.children)) na_collect(descriptor.children, group, into, id || parent);
    }
}

function na_descriptor_arrays(sandbox, before) {
    return Object.keys(sandbox).filter((key) => !before.has(key) && /^NA_[A-Z0-9_]+$/.test(key) && Array.isArray(sandbox[key]))
        .filter((key) => sandbox[key].some((item) => item && typeof item === 'object' && (item.id || item.children)));
}

// =============================================================================
// REGION | Sections (from the layout map)
// =============================================================================

function na_sections(spec) {
    if (!spec || !Array.isArray(spec.sections)) return { sections: [], placement: {} };
    const placement = {};
    const sections = spec.sections.map((section) => {
        const items = (section.items || []).filter((item) => item && item.id);
        items.forEach((item) => {
            const row = { section: section.key, section_title: typeof section.title === 'string' ? section.title : section.key };
            if (item.kind) row.kind = item.kind;
            if (item.tier) row.tier = item.tier;
            if (item.group) row.ui_group = item.group;
            if (Array.isArray(item.products)) row.products = item.products.slice();
            else if (Array.isArray(section.products)) row.products = section.products.slice();
            if (item.kw) row.keywords = item.kw;
            if (item.need && item.need.text) row.needs = item.need.text;
            if (!placement[item.id]) placement[item.id] = row;
        });
        return { key: section.key, title: section.title, products: Array.isArray(section.products) ? section.products.slice() : undefined,
                 items: items.map((item) => item.id) };
    });
    return { sections: na_clean(sections), placement: placement };
}

// =============================================================================
// REGION | What Each Dialog Starts From
// =============================================================================

const NA_DIALOG_DEFAULTS_NOTE = {
    window_family: 'Every control default, children included (MainUiLogic na_init). The dialog then merges the Ruby defaults (WindowSystem Defaults NA_DEFAULT_CONFIG) over these: the seam does the same.',
    interior_door: 'Top-level control defaults plus the material ids MainUiLogic seeds (NA_DOOR_MATERIAL_DEFAULTS), without the UI-only leaf sizes. This is what the dialog sends for a new door, NOT the Ruby NA_DEFAULT_DOOR_CONFIG (which differs: floor clearance, swing side).',
    cabinet: 'Every control default. The dialog starts from the Ruby defaults (Cabinetry Defaults NA_DEFAULT_CABINET_CONFIG) and these fill any key they lack.'
};

// HELPER FUNCTION | A Constant Object Literal Read From a Dialog Source File
// ------------------------------------------------------------
// For a constant private to a module's closure. Fails loudly, so a renamed
// constant breaks the generator rather than the catalogue.
function na_read_literal(relative, constName) {
    const text = fs.readFileSync(path.join(NA_SRC_ROOT, relative), 'utf8');
    const match = new RegExp('var\\s+' + constName + '\\s*=\\s*(\\{[\\s\\S]*?\\}|\\[[\\s\\S]*?\\]);').exec(text);
    if (!match) throw new Error(constName + ' not found in ' + relative);
    return vm.runInNewContext('(' + match[1] + ')');
}

function na_dialog_defaults(name, sandbox, arrays) {
    const out = {};
    if (name === 'interior_door') {
        const ui = '40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__UiSystem__MainUiLogic__.js';
        arrays.forEach((key) => (sandbox[key] || []).forEach((descriptor) => {
            if (descriptor && descriptor.id) out[descriptor.id] = na_clean(descriptor.default);
        }));
        const materials = na_read_literal(ui, 'NA_DOOR_MATERIAL_DEFAULTS');
        Object.keys(materials).forEach((key) => { if (!(key in out)) out[key] = materials[key]; });
        na_read_literal(ui, 'NA_DOOR_DERIVED_UI_KEYS').forEach((key) => { delete out[key]; });
        na_read_literal(ui, 'NA_DOOR_OBSOLETE_CONFIG_KEYS').forEach((key) => { delete out[key]; });
        return out;
    }
    const walk = (list) => (list || []).forEach((descriptor) => {
        if (!descriptor || typeof descriptor !== 'object') return;
        if (descriptor.id && descriptor.default !== undefined) out[descriptor.id] = na_clean(descriptor.default);
        if (Array.isArray(descriptor.children)) walk(descriptor.children);
    });
    arrays.forEach((key) => walk(sandbox[key]));
    return out;
}

// =============================================================================
// REGION | Build
// =============================================================================

function na_build_system(name, spec) {
    const sandbox = na_sandbox();
    const controls = {};
    const arrays = [];
    for (const relative of spec.configs) {
        const before = new Set(Object.keys(sandbox));
        na_run(sandbox, relative);
        for (const key of na_descriptor_arrays(sandbox, before)) {
            arrays.push(key);
            na_collect(sandbox[key], key, controls);
        }
    }

    const patterns = [];
    if (name === 'window_family') {
        if (typeof sandbox.na_buildMullionOffsetDescriptors === 'function') na_collect(sandbox.na_buildMullionOffsetDescriptors(), 'mullion_offsets', controls);
        if (typeof sandbox.na_buildGlazebarOffsetDescriptors === 'function') {
            na_collect(sandbox.na_buildGlazebarOffsetDescriptors('horizontal', 'Horizontal'), 'glazebar_offsets', controls);
            na_collect(sandbox.na_buildGlazebarOffsetDescriptors('vertical', 'Vertical'), 'glazebar_offsets', controls);
        }
        if (typeof sandbox.na_buildArchedHeaderDescriptor === 'function') {
            ['', 'single_door_', 'double_door_', 'sliding_door_', 'bifold_door_'].forEach((prefix) => {
                const descriptor = sandbox.na_buildArchedHeaderDescriptor(prefix);
                na_collect(Array.isArray(descriptor) ? descriptor : [descriptor], 'arched_header', controls);
            });
        }
        if (Array.isArray(sandbox.NA_CASEMENT_OVERRIDE_FIELDS)) {
            patterns.push({
                pattern: 'casement_overrides[<opening>:<cell>:<panel>].<field>',
                note: 'Per Casement Settings: not flat keys. The window stores them in config.casement_overrides, keyed by casement "o:c:p".',
                fields: na_clean(sandbox.NA_CASEMENT_OVERRIDE_FIELDS)
            });
        }
    }

    sandbox.__registered = sandbox.__registered || {};
    const before = new Set(Object.keys(sandbox));
    try {
        na_run(sandbox, spec.layout);
    } catch (error) {
        console.error('layout map of ' + name + ' did not run: ' + error.message);
    }
    void before;
    const layoutSpec = sandbox.__registered[spec.tab] || Object.values(sandbox.__registered)[0];
    const layout = na_sections(layoutSpec);
    // Layout items that are not settings (a leaf picker, a finish block) are
    // left out; a switch group is a setting (its open state is stored).
    for (const [id, row] of Object.entries(layout.placement)) {
        if (controls[id]) Object.assign(controls[id], row);
        else if (!row.kind || row.kind === 'control' || row.kind === 'switchgroup') controls[id] = Object.assign({ group: 'layout_only' }, row);
    }
    for (const record of Object.values(controls)) {
        if (record.materialsSource) record.options_from = 'entity_studio assets (finishes / edge colours): the dialog fills ' + record.materialsSource + ' from Ruby at runtime';
    }

    const sorted = {};
    Object.keys(controls).sort().forEach((key) => { sorted[key] = controls[key]; });
    const products = layoutSpec && Array.isArray(layoutSpec.products)
        ? layoutSpec.products.map((product) => { const row = na_clean(product); delete row.icon; return row; })
        : undefined;
    return {
        tab: spec.tab,
        sources: spec.configs.concat([spec.layout]),
        descriptor_arrays: arrays,
        products: products,
        product_defaults: name === 'cabinet' && sandbox.NA_CABINET_PRODUCT_DEFAULTS ? na_clean(sandbox.NA_CABINET_PRODUCT_DEFAULTS) : undefined,
        dialog_defaults: na_dialog_defaults(name, sandbox, arrays),
        dialog_defaults_note: NA_DIALOG_DEFAULTS_NOTE[name],
        hidden_in_dialog: layoutSpec ? na_clean(layoutSpec.hiddenIds) : undefined,
        sections: layout.sections,
        patterns: patterns,
        control_count: Object.keys(sorted).length,
        controls: sorted
    };
}

function na_build() {
    const systems = {};
    for (const [name, spec] of Object.entries(NA_SYSTEMS)) systems[name] = na_build_system(name, spec);
    return {
        meta: {
            description: 'Every control the Element Assembly Studio Pro dialog shows, per system. Generated: do not edit by hand.',
            generator: '65__Dev__DevTools/Na__AssemblyStudio__DevTools__ParameterCatalogue__.js',
            rerun: 'node Na__AssemblyStudio__DevTools__ParameterCatalogue__.js (after changing any *UiSystem__Config__.js or *LayoutMap__.js)',
            note: 'Values stored on an element hold more keys than these controls (removal lists, per-casement overrides, edge colour ids): the defaults and presets carry them.'
        },
        systems: systems
    };
}

// =============================================================================
// REGION | Main
// =============================================================================

const catalogue = na_build();
const text = JSON.stringify(catalogue, null, 1) + '\n';
if (process.argv.includes('--check')) {
    const current = fs.existsSync(NA_OUT_FILE) ? fs.readFileSync(NA_OUT_FILE, 'utf8') : '';
    if (current !== text) {
        console.error('STALE: ' + NA_OUT_FILE + ' differs from the dialog files. Run this script without --check.');
        process.exit(1);
    }
    console.log('PASS: parameter catalogue is current (' + Object.entries(catalogue.systems).map(([k, v]) => k + ' ' + v.control_count).join(', ') + ').');
} else {
    fs.writeFileSync(NA_OUT_FILE, text);
    console.log('Wrote ' + NA_OUT_FILE);
    for (const [name, system] of Object.entries(catalogue.systems)) {
        console.log('  ' + name + ': ' + system.control_count + ' controls, ' + system.sections.length + ' sections, arrays ' + system.descriptor_arrays.join(' '));
    }
}

/* =============================================================================
   END OF FILE
   ============================================================================= */
