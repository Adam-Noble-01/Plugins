/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - LAYOUT COVERAGE SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__LayoutCoverage__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Guards the V2.0.0 section layout. Every control the three
                configurator tabs build has a slot in its tab's layout map,
                and every slot names a control that still exists.
   CREATED    : 28-Oct-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__LayoutCoverage__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHY THIS EXISTS:
   The UiSystem Config files still say WHAT the controls are; the LayoutMap
   files say WHERE each one lives. A control added to a config without a slot
   still appears (Na__Ui__SectionLayout sweeps it into Output > Advanced >
   Other and warns in the console), but nobody reads that console inside
   SketchUp. A renamed or removed control leaves its slot empty, and its
   "Turn It On" fix in the search sets a key nothing reads, with no warning
   at all. This suite fails on all three before the dialog is opened.

   It loads the SHIPPED config and layout-map files unmodified, with
   Na__Ui__SectionLayout replaced by a stub that captures each registered
   layout, then replays the rule of na_sweep_leftovers against the
   descriptor trees.

   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');


// -----------------------------------------------------------------------------
// REGION | Harness
// -----------------------------------------------------------------------------

const NA_ROOT    = path.resolve(__dirname, '..');
const NA_MODULES = path.join(NA_ROOT, '02__Src__AppModules');

let na_pass = 0;
let na_fail = 0;

// HELPER FUNCTION | Assert Deep Equality and Record the Outcome
// ------------------------------------------------------------
function na_expect(label, actual, expected) {
    if (JSON.stringify(actual) === JSON.stringify(expected)) {
        na_pass += 1;
        return;
    }
    na_fail += 1;
    console.log('  FAIL  ' + label + '\n        got  ' + JSON.stringify(actual) +
                '\n        want ' + JSON.stringify(expected));
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Print a Suite Heading
// ------------------------------------------------------------
function na_suite(title) {
    console.log('\n' + title);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Read One Shipped Source File
// ------------------------------------------------------------
function na_read(relativePath) {
    return fs.readFileSync(path.join(NA_MODULES, relativePath), 'utf8');
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Stubs and Shipped Modules
// -----------------------------------------------------------------------------

// Nothing here is drawn: the layout maps only need somewhere to register.
const NA_LAYOUTS = {};

global.window   = global;
global.document = {
    getElementById   : () => null,
    querySelector    : () => null,
    querySelectorAll : () => [],
    addEventListener : () => {}
};
window.Na__Ui__SectionLayout = { na_register: (tabId, spec) => { NA_LAYOUTS[tabId] = spec; } };

const NA_SOURCES = [
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__Config__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js',
    '40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__UiSystem__Config__.js',
    '45__System__InteriorCabinetry/Na__AssemblyStudio__Cabinetry__UiSystem__Config__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__LayoutMap__.js',
    '40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__UiSystem__LayoutMap__.js',
    '45__System__InteriorCabinetry/Na__AssemblyStudio__Cabinetry__UiSystem__LayoutMap__.js'
];

// Each shipped file declares top-level `const`s, which would collide across a
// shared eval scope, so every source is evaluated in its own function scope.
const na_console_log = console.log;
console.log = () => {};
NA_SOURCES.forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + na_read(relativePath) + '\n})()');
});
console.log = na_console_log;

const NA_PAGE_HTML = fs.readFileSync(path.join(NA_ROOT, 'Na__AssemblyStudio__UiLayout__.html'), 'utf8');

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | What Each Tab Builds
// -----------------------------------------------------------------------------

// The Windows tab draws these arrays (WindowSystem MainUiLogic na_init) with
// Na__Ui__Controls.na_createControl, which draws nothing for any other type.
const NA_TABS = {
    windows: {
        arrays: ['NA_UI_CONFIG', 'NA_GLAZEBAR_CONFIG', 'NA_CILL_FRAME_CONFIG', 'NA_OPTIONS_CONFIG',
                 'NA_WINDOW_BOARD_CONFIG', 'NA_DOOR_PANEL_CONFIG', 'NA_SLIDING_DOOR_CONFIG',
                 'NA_BIFOLD_DOOR_CONFIG', 'NA_DOUBLE_DOOR_CONFIG'],
        types : ['slider', 'toggle', 'binary_toggle', 'multiway_toggle', 'eq_number', 'select',
                 'color', 'material_cards', 'expandable']
    },
    // The Interior Doors tab draws these (InteriorDoor MainUiLogic na_mount)
    // with its own na_build_control, which has no containers.
    doors: {
        arrays: ['NA_DOOR_OPENING_CONFIG', 'NA_DOOR_PANEL_TAB_CONFIG', 'NA_DOOR_ARCHITRAVE_CONFIG',
                 'NA_DOOR_HANDLE_CONFIG', 'NA_DOOR_OPTIONS_CONFIG'],
        types : ['slider', 'select', 'binary_toggle', 'checkbox']
    },
    // The Cabinetry tab draws these (Cabinetry MainUiLogic NA_CONTAINERS)
    // with the shared Na__Ui__Controls engine.
    cabinets: {
        arrays: ['NA_CABINET_PRODUCT_CONFIG', 'NA_CABINET_SIZE_CONFIG', 'NA_CABINET_FRONTS_CONFIG',
                 'NA_CABINET_INTERIOR_CONFIG', 'NA_CABINET_CARCASS_CONFIG', 'NA_CABINET_PLINTH_CONFIG',
                 'NA_CABINET_HARDWARE_CONFIG', 'NA_CABINET_FINISH_CONFIG', 'NA_CABINET_OUTPUT_CONFIG'],
        types : ['slider', 'toggle', 'binary_toggle', 'multiway_toggle', 'select', 'material_cards']
    }
};

const NA_TAB_TITLES = { windows: 'Windows & Exterior Doors tab', doors: 'Interior Doors tab', cabinets: 'Cabinetry tab' };

// HELPER FUNCTION | Every Built Control as { id, parentId }, Containers First
// ------------------------------------------------------------
function na_built_controls(tab) {
    const out = [];
    const walk = (descriptors, parentId) => (descriptors || []).forEach(descriptor => {
        if (!descriptor || !descriptor.id || tab.types.indexOf(descriptor.type) === -1) return;
        out.push({ id: descriptor.id, parentId: parentId, children: descriptor.children || [] });
        walk(descriptor.children, descriptor.id);
    });
    tab.arrays.forEach(name => walk(window[name], null));
    return out;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Every Item of a Registered Layout, With Its Section
// ------------------------------------------------------------
function na_layout_items(layout) {
    const items = [];
    (layout.sections || []).forEach(section => (section.items || []).forEach(item => items.push(Object.assign({ section: section.key }, item))));
    return items;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Replay na_sweep_leftovers Against the Descriptors
// ------------------------------------------------------------
// A placed control takes its whole subtree with it. Whatever is left in the
// staging container is swept when it is neither placed nor hidden and has no
// parent, or only a hidden parent (a box whose contents are laid out one by
// one). A child of any other parent travels with that parent.
function na_leftovers(built, mapped, hidden) {
    const byId     = {};
    const leftover = [];
    built.forEach(control => { byId[control.id] = control; });
    const placedAbove = control => {
        for (let parent = byId[control.parentId]; parent; parent = byId[parent.parentId]) {
            if (mapped.has(parent.id)) return true;
        }
        return false;
    };
    built.forEach(control => {
        if (mapped.has(control.id) || hidden.has(control.id) || placedAbove(control)) return;
        if (control.parentId === null || hidden.has(control.parentId)) leftover.push(control.id);
    });
    return leftover;
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suites
// -----------------------------------------------------------------------------

Object.keys(NA_TABS).forEach(tabId => {
    const tab    = NA_TABS[tabId];
    const layout = NA_LAYOUTS[tabId];

    na_suite(NA_TAB_TITLES[tabId]);
    na_expect('Layout map registered', !!layout, true);
    if (!layout) return;

    const built       = na_built_controls(tab);
    const builtIds    = new Set(built.map(control => control.id));
    const items       = na_layout_items(layout);
    const controlSlot = item => item.kind !== 'block' && item.kind !== 'picker';
    const mapped      = new Set(items.filter(controlSlot).map(item => item.id));
    const hidden      = new Set(layout.hiddenIds || []);
    const sectionKeys = (layout.sections || []).map(section => section.key);
    const productKeys = (layout.products || []).map(product => product.key);

    console.log('  ' + built.length + ' controls built, ' + items.length + ' layout items, ' +
                sectionKeys.length + ' sections, ' + productKeys.length + ' products');

    na_expect('Every built control has a slot (or is hidden on purpose)',
              na_leftovers(built, mapped, hidden), []);

    na_expect('Every slot names a control the tab builds',
              items.filter(controlSlot).map(item => item.id).filter(id => !builtIds.has(id)), []);

    const seen = {};
    na_expect('No control has two slots',
              items.map(item => item.id).filter(id => (seen[id] = (seen[id] || 0) + 1) === 2), []);

    na_expect('Every hidden id is a control the tab builds',
              [...hidden].filter(id => !builtIds.has(id)), []);

    na_expect('Every static block is on the page',
              items.filter(item => item.kind === 'block').map(item => item.id)
                   .filter(id => NA_PAGE_HTML.indexOf('id="' + id + '"') === -1), []);

    const fixIds = [];
    items.forEach(item => ((item.need && item.need.fix) || []).forEach(pair => fixIds.push(pair[0])));
    na_expect('Every "Turn It On" fix sets a control the tab builds',
              [...new Set(fixIds)].filter(id => !builtIds.has(id)), []);

    const named = [];
    (layout.sections || []).forEach(section => named.push(...(section.products || [])));
    items.forEach(item => named.push(...(item.products || [])));
    na_expect('Every product a section or item names is in the product strip',
              [...new Set(named)].filter(key => productKeys.indexOf(key) === -1), []);

    if (typeof layout.orderFor === 'function') {
        const unknown = [];
        const ordered = new Set();
        productKeys.forEach(product => layout.orderFor(product).forEach(key => {
            ordered.add(key);
            if (sectionKeys.indexOf(key) === -1) unknown.push(product + ':' + key);
        }));
        na_expect('Every section order names real sections', unknown, []);
        na_expect('Every section is in some product\'s order',
                  sectionKeys.filter(key => !ordered.has(key)), []);
    }
});

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);

/* =============================================================================
   END OF FILE
   ============================================================================= */
