/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - GLAZED OVER GLAZED DOOR LEAVES SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__GlazedOverGlazed__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for V2.3.0 - the Glazed Over Glazed leaf
                composition on single, double, sliding and bifold doors.
   CREATED    : 02-Nov-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__GlazedOverGlazed__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   The door the numbers come from: a 900 x 2000 leaf with 95 stiles and top
   rail, a 200 bottom rail, a 120 mid rail and a 600 lower pane. So the lower
   glass is 600 tall and the top glass 985, and nine horizontal lead lines in
   the top pane become five in the lower one (same size of quarry).

   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');


// -----------------------------------------------------------------------------
// REGION | Harness
// -----------------------------------------------------------------------------

const NA_MODULES = path.resolve(__dirname, '..', '02__Src__AppModules');

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

// HELPER FUNCTION | A Recording SVG Node
// ------------------------------------------------------------
function na_make_node(tag) {
    const node = {
        tag: tag, attrs: {}, children: [], textContent: '',
        setAttribute: (name, value) => { node.attrs[name] = value; },
        appendChild : (child) => { node.children.push(child); return child; },
        removeChild : (child) => {
            const index = node.children.indexOf(child);
            if (index >= 0) node.children.splice(index, 1);
            return child;
        }
    };
    Object.defineProperty(node, 'firstChild', { get: () => (node.children.length ? node.children[0] : null) });
    return node;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Flatten a Rendered Node Tree
// ------------------------------------------------------------
function na_flatten(node, collected) {
    collected = collected || [];
    node.children.forEach((child) => {
        collected.push(child);
        na_flatten(child, collected);
    });
    return collected;
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Stub and Shipped Modules
// -----------------------------------------------------------------------------

let na_onControlChange = null;
global.window   = global;
global.document = {
    createElementNS  : (ns, tag) => na_make_node(tag),
    createElement    : () => ({ appendChild: () => {} }),
    getElementById   : (id) => (String(id).indexOf('na-controls-') === 0 ? { innerHTML: '', insertAdjacentHTML: () => {} } : null),
    querySelector    : () => null,
    querySelectorAll : () => [],
    addEventListener : () => {}
};
window.Na__Ui__Controls = { na_createControl: () => '' };
window.Na__Ui__Events   = { na_attachEventListeners: (config, callback) => { na_onControlChange = callback; } };
const na_console_error  = console.error;
console.error = (message, ...rest) => {                              // <-- No viewport is built here; keep every other error
    if (String(message).indexOf('[NA_VIEWPORT]') === 0) return;
    na_console_error(message, ...rest);
};

const NA_SOURCES = [
    '03__AppUtils/Na__AssemblyStudio__AppUtils__ArithmeticEvaluator__.js',
    '05__Viewport__2dPreviewEngine/Na__AssemblyStudio__Viewport__SvgHelpers__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__Config__.js',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__PanelConfigResolver__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__MullionMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__CasementMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js',
    '30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__UiSystem__LeafConfigResolver__.js',
    '30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__Viewport__ElevationGenerator__.js',
    '30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__Viewport__PlanGenerator__.js',
    '30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__UiSystem__DxfExporter__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__LeafConfigResolver__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__Viewport__ElevationGenerator__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__Viewport__PlanGenerator__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__DxfExporter__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__LeafConfigResolver__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__Viewport__ElevationGenerator__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__Viewport__PlanGenerator__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__DxfExporter__.js',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__Viewport__ElevationGenerator__.js',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__Viewport__ElevationGenerator__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__MainUiLogic__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Bridge__.js'
];
const na_console_log = console.log;
console.log = () => {};
NA_SOURCES.forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + fs.readFileSync(path.join(NA_MODULES, relativePath), 'utf8') + '\n})()');
});
const Ui = window.Na_DynamicUI;
Ui.na_init();
console.log = (message, ...rest) => {                                // <-- Keep the suite's output, drop the dialog's own [NA_*] logging
    if (String(message).indexOf('[NA_') === 0) return;
    na_console_log(message, ...rest);
};

const Maths = window.Na__GlazebarMath;

// HELPER FUNCTION | A Single Door Config for the Door in the Header
// ------------------------------------------------------------
function na_single(overrides) {
    const seeded = {};
    window.NA_EXT_SINGLE_DOOR_CONFIG.forEach((item) => {
        if (item && typeof item.id === 'string' && item.id.indexOf('single_door_') === 0) seeded[item.id] = item.default;
    });
    return Object.assign({
        ext_single_door_mode: true, width_mm: 1000, height_mm: 2100, frame_thickness_mm: 50, frame_depth_mm: 70,
        frame_wall_inset_mm: 0, has_cill: false, show_dimensions: false,
        horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25, glazebar_inset_mm: 10,
        leaded_glass_enabled: true, horizontal_leaded_bars: 9, vertical_leaded_bars: 5, leaded_width_mm: 6,
        leaded_centre_lines_only: true
    }, seeded, {
        single_door_leaf_composition: 'GlazedOverGlazed', single_door_panel_stile_width_mm: 95,
        single_door_panel_top_rail_width_mm: 95, single_door_panel_bottom_rail_width_mm: 200,
        single_door_mid_rail_width_mm: 120, single_door_fielded_section_height_mm: 600
    }, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Render the Single Door Elevation to Nodes
// ------------------------------------------------------------
function na_render_single(config) {
    const root = na_make_node('svg');
    window.Na__ExtSingleDoor__ElevationGenerator.na_render(root, config);
    return na_flatten(root);
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suites
// -----------------------------------------------------------------------------

na_suite('Line counts for the lower pane');
na_expect('nine lines, 600 pane under a 985 pane: five', Maths.na_scaleLineCount(9, 600 / 985), 5);
na_expect('no lines stay no lines', Maths.na_scaleLineCount(0, 2), 0);
na_expect('never below zero', Maths.na_scaleLineCount(1, 0.1), 0);
na_expect('never above twelve', Maths.na_scaleLineCount(12, 3), 12);
const na_no_bars = Maths.na_lowerPaneLayout(0, 985, 600);
na_expect('no glaze bars: cell 1, none added', [na_no_bars.cellIndex, na_no_bars.hBars], [1, 0]);
na_expect('no glaze bars: lead scales with the pane', Maths.na_scaleLineCount(9, na_no_bars.leadRatio), 5);
const na_two_bars = Maths.na_lowerPaneLayout(2, 985, 600);
na_expect('two bars above: one below', na_two_bars.hBars, 1);
na_expect('with bars the panes between them match, so lead stays near the same', Maths.na_scaleLineCount(3, na_two_bars.leadRatio), 3);

na_suite('The option is on every door type');
[window.NA_EXT_SINGLE_DOOR_CONFIG, window.NA_EXT_DOUBLE_DOOR_CONFIG].forEach((descriptors, index) => {
    const composition = descriptors.find(item => item && /_leaf_composition$/.test(item.id || ''));
    na_expect('hinged list ' + index + ' offers it', composition.options.some(option => option.value === 'GlazedOverGlazed'), true);
});
na_expect('sliding offers it', /GlazedOverGlazed/.test(fs.readFileSync(path.join(NA_MODULES, '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js'), 'utf8')), true);
na_expect('bifold offers it', /GlazedOverGlazed/.test(fs.readFileSync(path.join(NA_MODULES, '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__Config__.js'), 'utf8')), true);

na_suite('Leaf layout (hinged)');
const Single = window.Na__ExtSingleDoor__LeafConfigResolver;
const na_panel = Single.na_resolve(na_single()).leaves[0].panelLayout;
na_expect('no fielded section, no cells', [na_panel.fieldRegion, na_panel.fieldCells.length], [null, 0]);
na_expect('lower glass 710 x 600 from the bottom rail', [na_panel.lowerGlazedRegion.xMm, na_panel.lowerGlazedRegion.zMm, na_panel.lowerGlazedRegion.widthMm, na_panel.lowerGlazedRegion.heightMm], [145, 250, 710, 600]);
na_expect('mid rail on top of it', na_panel.midRailZMm, 850);
na_expect('top glass above the rail', [na_panel.glazedRegion.zMm, na_panel.glazedRegion.heightMm], [970, 985]);
na_expect('it validates (no fielded panels to fit)', Single.na_validate(na_single()).errors, []);
const na_fielded = Single.na_resolve(na_single({ single_door_leaf_composition: 'GlazedOverFielded' })).leaves[0].panelLayout;
na_expect('Glazed Over Fielded still has its field and no lower glass', [na_fielded.fieldRegion.heightMm, na_fielded.lowerGlazedRegion, na_fielded.midRailZMm], [600, null, 850]);
const na_full = Single.na_resolve(na_single({ single_door_leaf_composition: 'FullyGlazed' })).leaves[0].panelLayout;
na_expect('Fully Glazed has no mid rail', [na_full.midRailZMm, na_full.lowerGlazedRegion], [null, null]);

na_suite('Hinged door preview');
const na_nodes = na_render_single(na_single());
const na_lines = na_nodes.filter(node => node.tag === 'line' && node.attrs['stroke-width'] === 1);
const na_rows = na_lines.filter(node => node.attrs.y1 === node.attrs.y2);
const na_cols = na_lines.filter(node => node.attrs.x1 === node.attrs.x2);
na_expect('nine rows above plus five below', na_rows.length, 14);
na_expect('five verticals in each pane', na_cols.length, 10);
const na_col_xs = [...new Set(na_cols.map(node => Math.round(node.attrs.x1 * 1000) / 1000))];
na_expect('and they line up (five positions, not ten)', na_col_xs.length, 5);
const na_cells = na_nodes.filter(node => node.attrs.class === 'na-leaded-cell-click-target');
na_expect('a lead click target per pane, cells 0 and 1', na_cells.map(node => node.attrs['data-cell-index']), [0, 1]);
const na_disabled = na_render_single(na_single({ single_door_leaded_disabled_cells: ['0:1:0:0:0:0'] }))
    .filter(node => node.tag === 'line' && node.attrs['stroke-width'] === 1);
na_expect('switching the lower pane\'s lead off leaves the top pane\'s', na_disabled.length, 14);
const na_bars = na_render_single(na_single({ horizontal_glaze_bars: 2, vertical_glaze_bars: 1, single_door_horizontal_glaze_bars: 2, single_door_vertical_glaze_bars: 1 }))
    .filter(node => node.attrs.class === 'na-glazebar-click-target');
na_expect('glaze bars: 2 + 1 above, 1 + 1 below', ['0', '1'].map(cell => na_bars.filter(node => String(node.attrs['data-cell-index']) === cell).length), [3, 2]);
const na_fully = na_render_single(na_single({ single_door_leaf_composition: 'FullyGlazed' }))
    .filter(node => node.attrs.class === 'na-leaded-cell-click-target');
na_expect('Fully Glazed keeps one pane', na_fully.length, 1);

na_suite('Hinged door DXF');
const na_dxf = window.Na__ExtSingleDoor__DxfExporter.na_export_dxf(na_single());
na_expect('exports', typeof na_dxf, 'string');
const na_layer_lines = (layer) => na_dxf.split('\n').map(line => line.trim()).filter(line => line === layer).length;
const na_dxf_fully = window.Na__ExtSingleDoor__DxfExporter.na_export_dxf(na_single({ single_door_leaf_composition: 'FullyGlazed' }));
const na_count = (text, layer) => text.split('\n').map(line => line.trim()).filter(line => line === layer).length;
na_expect('twice the glass of a Fully Glazed leaf', na_layer_lines('NA_GLASS'), na_count(na_dxf_fully, 'NA_GLASS') * 2);
na_expect('and a mid rail more', na_layer_lines('NA_RAIL_STILE') > na_count(na_dxf_fully, 'NA_RAIL_STILE'), true);

na_suite('Sliding and bifold previews');
const na_set_door = {
    width_mm: 3000, height_mm: 2100, frame_thickness_mm: 50, has_cill: false, show_dimensions: false,
    horizontal_glaze_bars: 2, vertical_glaze_bars: 1, glaze_bar_width_mm: 25,
    leaded_glass_enabled: true, horizontal_leaded_bars: 3, vertical_leaded_bars: 2, leaded_width_mm: 6
};
const na_slide = window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg(Object.assign({}, na_set_door, {
    sliding_mode: true, sliding_door_leaf_composition: 'GlazedOverGlazed', sliding_door_fielded_section_height_mm: 600, sliding_door_mid_rail_width_mm: 120
}));
na_expect('sliding: glaze bars in cell 1', /na-glazebar-click-target"[^>]*data-cell-index="1"/.test(na_slide), true);
na_expect('sliding: lead in cell 1', /na-leaded-cell-click-target"[^>]*data-cell-index="1"/.test(na_slide), true);
const na_slide_plain = window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg(Object.assign({}, na_set_door, { sliding_mode: true, sliding_door_leaf_composition: 'FullyGlazed' }));
na_expect('sliding, Fully Glazed: no cell 1', /data-cell-index="1"/.test(na_slide_plain), false);
const na_fold = window.Na__ExtFold__ElevationGenerator.na_generate_bifold_svg(Object.assign({}, na_set_door, {
    multifold_mode: true, bifold_door_leaf_composition: 'GlazedOverGlazed', bifold_door_fielded_section_height_mm: 600, bifold_door_mid_rail_width_mm: 120
}));
na_expect('bifold: glaze bars in cell 1', /na-glazebar-click-target"[^>]*data-cell-index="1"/.test(na_fold), true);
na_expect('bifold: lead in cell 1', /na-leaded-cell-click-target"[^>]*data-cell-index="1"/.test(na_fold), true);
na_expect('bifold validates', window.Na__ExtFold__PanelConfigResolver.na_validate(Object.assign({}, na_set_door, {
    multifold_mode: true, bifold_door_leaf_composition: 'GlazedOverGlazed' })).errors, []);

na_suite('Panel: removal keys and the legacy flag');
Ui.na_setConfig(na_single({ ui_element_category: 'ExteriorDoors', ui_exterior_door_type: 'Single', horizontal_glaze_bars: 2, vertical_glaze_bars: 1, single_door_horizontal_glaze_bars: 2, single_door_vertical_glaze_bars: 1 }));
Ui.na_toggleExtDoorGlazebarRemoval(0, 1, 0, 0, 'vertical', 1);
na_expect('a lower pane bar stays clicked off through the clean up', Ui.na_getConfig().single_door_removed_glazebars, ['0:1:0:0:vertical:1']);
Ui.na_toggleExtDoorLeadedCellState(0, 1, 0, 0, 0, 0);
na_expect('a lower pane lead cell too', Ui.na_getConfig().single_door_leaded_disabled_cells, ['0:1:0:0:0:0']);
Ui.na_setConfig({ single_door_leaf_composition: 'FullyGlazed' });
na_expect('leaving the composition drops them', [Ui.na_getConfig().single_door_removed_glazebars, Ui.na_getConfig().single_door_leaded_disabled_cells], [[], []]);
Ui.na_setConfig({ bifold_door_leaf_composition: 'GlazedOverGlazed' });
na_expect('bifold legacy flag reads as glazed', Ui.na_getConfig().bifold_door_glazed, true);

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);
