/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR PARITY SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__ExteriorDoorParity__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for the V1.5.3 exterior-door parity work - the
                Exterior Single Door and the Exterior Double Door now resolve,
                preview and export through one shared ExtDoorCommon code path.
   CREATED    : 29-Aug-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__ExteriorDoorParity__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHY THIS EXISTS:
   The bug this suite pins down is silent: a single exterior door used to fall
   through to the WindowSystem casement generator, so every fielded-panel
   control in its section changed the config and changed nothing on screen or
   in SketchUp. Nothing threw - the door simply drew as a window. These
   assertions check the two products agree leaf-for-leaf on the panel maths
   they share, and that the single door actually honours composition, preset,
   rails and swing side.

   The suite loads the SHIPPED source files unmodified against a minimal DOM /
   window stub, so it tests what actually runs in the dialog.

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

// HELPER FUNCTION | Assert a Condition Holds
// ------------------------------------------------------------
function na_assert(label, condition) {
    na_expect(label, condition === true, true);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Assert Two Numbers Agree Within a Tolerance
// ------------------------------------------------------------
function na_close(label, actual, expected, tolerance) {
    const within = Math.abs(Number(actual) - Number(expected)) <= (tolerance || 0.001);
    if (within) { na_pass += 1; return; }
    na_fail += 1;
    console.log('  FAIL  ' + label + '\n        got  ' + actual + '\n        want ~' + expected);
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
// REGION | Minimal SVG / DOM Stub
// -----------------------------------------------------------------------------

// The generators only ever create SVG nodes and append them, so a node that
// records its tag plus attributes is enough to assert on the drawn output.
function na_make_node(tag) {
    const node = {
        tag         : tag,
        attrs       : {},
        children    : [],
        textContent : '',
        setAttribute: (name, value) => { node.attrs[name] = value; },
        appendChild : (child) => { node.children.push(child); return child; },
        removeChild : (child) => {
            const index = node.children.indexOf(child);
            if (index >= 0) node.children.splice(index, 1);
            return child;
        }
    };
    Object.defineProperty(node, 'firstChild', {
        get: () => (node.children.length ? node.children[0] : null)
    });
    return node;
}

global.window   = global;
global.document = { createElementNS: (ns, tag) => na_make_node(tag) };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Load the Shipped Modules
// -----------------------------------------------------------------------------

const NA_SOURCES = [
    '05__Viewport__2dPreviewEngine/Na__AssemblyStudio__Viewport__SvgHelpers__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js',
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
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js'
];

// Each shipped file declares a top-level `const`, which would collide across a
// shared eval scope, so every source is evaluated in its own function scope.
NA_SOURCES.forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + na_read(relativePath) + '\n})()');
});

const Single = window.Na__ExtSingleDoor__LeafConfigResolver;
const Double = window.Na__ExtDouble__LeafConfigResolver;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Config Builders
// -----------------------------------------------------------------------------

// HELPER FUNCTION | Base Opening Shared by Both Products
// ------------------------------------------------------------
function na_opening(overrides) {
    return Object.assign({
        width_mm               : 1000,
        height_mm              : 2100,
        frame_thickness_mm     : 50,
        frame_depth_mm         : 70,
        frame_wall_inset_mm    : 0,
        has_cill               : false,
        show_dimensions        : true,
        horizontal_glaze_bars  : 2,
        vertical_glaze_bars    : 1,
        glaze_bar_width_mm     : 25,
        glazebar_inset_mm      : 10
    }, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Seed One Product's Keys from its Shipped UI Defaults
// ------------------------------------------------------------
// Using the shipped descriptor defaults rather than hand-written literals
// means a control whose default drifts is caught here rather than in SketchUp.
function na_defaults_for(descriptors, prefix) {
    const seeded = {};
    descriptors.forEach((item) => {
        if (!item || typeof item.id !== 'string') return;
        if (item.id.indexOf(prefix + '_') !== 0) return;
        seeded[item.id] = item.default;
    });
    return seeded;
}
// ---------------------------------------------------------------

const NA_SINGLE_DEFAULTS = na_defaults_for(window.NA_EXT_SINGLE_DOOR_CONFIG, 'single_door');
const NA_DOUBLE_DEFAULTS = na_defaults_for(window.NA_EXT_DOUBLE_DOOR_CONFIG, 'double_door');

// HELPER FUNCTION | Full Single-Door Config
// ------------------------------------------------------------
function na_single(overrides) {
    return Object.assign(na_opening(), NA_SINGLE_DEFAULTS, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Full Double-Door Config
// ------------------------------------------------------------
function na_double(overrides) {
    return Object.assign(na_opening({ width_mm: 1900 }), NA_DOUBLE_DEFAULTS, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Flatten a Rendered SVG Node Tree
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

// HELPER FUNCTION | Render One Product Elevation and Return its Nodes
// ------------------------------------------------------------
function na_render_elevation(generator, config) {
    const root = na_make_node('svg');
    generator.na_render(root, config);
    return na_flatten(root);
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 1 - Modules Load and Expose the Same Surface
// -----------------------------------------------------------------------------

na_suite('Suite 1 | Module surface parity');

['na_resolve', 'na_effective_leaf_config', 'na_validate'].forEach((fn) => {
    na_assert('Single resolver exposes ' + fn, typeof Single[fn] === 'function');
    na_assert('Double resolver exposes ' + fn, typeof Double[fn] === 'function');
});

['na_render', 'na_fit_to_content'].forEach((fn) => {
    na_assert('Single elevation exposes ' + fn,
        typeof window.Na__ExtSingleDoor__ElevationGenerator[fn] === 'function');
    na_assert('Single plan exposes ' + fn,
        typeof window.Na__ExtSingleDoor__PlanGenerator[fn] === 'function');
});

na_assert('Single DXF exporter exposes na_export_dxf',
    typeof window.Na__ExtSingleDoor__DxfExporter.na_export_dxf === 'function');

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 2 - The Single Door Resolves One Full-Width Leaf
// -----------------------------------------------------------------------------

na_suite('Suite 2 | Single-door leaf geometry');

const resolvedSingle = Single.na_resolve(na_single());
na_expect('One leaf resolved', resolvedSingle.leaves.length, 1);
na_expect('Leaf index is 1', resolvedSingle.leaves[0].index, 1);
na_expect('Leaf spans the clear width', resolvedSingle.leaves[0].widthMm, 900);
na_expect('Leaf origin is the left reveal', resolvedSingle.leaves[0].originXMm, 50);
na_expect('Leaf height is the clear height', resolvedSingle.leaves[0].heightMm, 2000);
na_assert('The only leaf is the active leaf', resolvedSingle.leaves[0].isActive === true);

const leftHung  = Single.na_resolve(na_single({ single_door_swing_side: 'Left' })).leaves[0];
const rightHung = Single.na_resolve(na_single({ single_door_swing_side: 'Right' })).leaves[0];
na_expect('Left-hung pivots on the left jamb', leftHung.hingeXMm, 50);
na_expect('Left-hung latches on the right', leftHung.latchXMm, 950);
na_expect('Right-hung pivots on the right jamb', rightHung.hingeXMm, 950);
na_expect('Right-hung latches on the left', rightHung.latchXMm, 50);
na_expect('Left-hung closed latch bearing is 0deg', leftHung.closedLatchAngleDeg, 0);
na_expect('Right-hung closed latch bearing is 180deg', rightHung.closedLatchAngleDeg, 180);
na_expect('Left-hung inward swing is negative', Math.sign(leftHung.signedAngleDeg), -1);
na_expect('Right-hung inward swing is positive', Math.sign(rightHung.signedAngleDeg), 1);

const outward = Single.na_resolve(na_single({ single_door_swing_direction: 'Outward' })).leaves[0];
na_expect('Inward leaf sits on the near frame face', leftHung.originYMm, 0);
na_expect('Outward leaf sits on the far frame face', outward.originYMm, 20);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 3 - Panel Options Actually Change the Single Door
// -----------------------------------------------------------------------------
// This is the regression the whole exercise exists for: before V1.5.3 every
// assertion in this block would have described a plain casement window.

na_suite('Suite 3 | Single-door fielded panel options');

const glazedOverFielded = Single.na_resolve(na_single()).leaves[0].panelLayout;
na_assert('GlazedOverFielded has a field region', glazedOverFielded.fieldRegion !== null);
na_assert('GlazedOverFielded has a glazed region', glazedOverFielded.glazedRegion !== null);
na_expect('Default fielded section height honoured', glazedOverFielded.fieldRegion.heightMm, 300);

const fullyGlazed = Single.na_resolve(
    na_single({ single_door_leaf_composition: 'FullyGlazed' })
).leaves[0].panelLayout;
na_assert('FullyGlazed drops the field region', fullyGlazed.fieldRegion === null);
na_expect('FullyGlazed has no field cells', fullyGlazed.fieldCells.length, 0);

const fullyFielded = Single.na_resolve(
    na_single({ single_door_leaf_composition: 'FullyFielded' })
).leaves[0].panelLayout;
na_assert('FullyFielded drops the glazed region', fullyFielded.glazedRegion === null);
na_assert('FullyFielded still has field cells', fullyFielded.fieldCells.length > 0);

const NA_PRESET_CELLS = {
    OnePanel      : 1,
    TwoVertical   : 2,
    TwoHorizontal : 2,
    FourPanel     : 4,
    SixPanel      : 6
};
Object.keys(NA_PRESET_CELLS).forEach((preset) => {
    const layout = Single.na_resolve(na_single({
        single_door_leaf_composition : 'FullyFielded',
        single_door_panel_preset     : preset
    })).leaves[0].panelLayout;
    na_expect('Preset ' + preset + ' yields the right cell count',
        layout.fieldCells.length, NA_PRESET_CELLS[preset]);
});

const customGrid = Single.na_resolve(na_single({
    single_door_leaf_composition : 'FullyFielded',
    single_door_panel_preset     : 'Custom',
    single_door_panel_columns    : 3,
    single_door_panel_rows       : 2
})).leaves[0].panelLayout;
na_expect('Custom 3x2 yields six cells', customGrid.fieldCells.length, 6);
// Dividers span the whole field region, so a 3x2 grid needs two vertical
// muntins and one horizontal - not one per cell edge.
na_expect('Custom 3x2 yields three dividers', customGrid.fieldDividers.length, 3);
na_expect('Two of the three dividers are vertical',
    customGrid.fieldDividers.filter((d) => d.orientation === 'vertical').length, 2);

const fatStiles = Single.na_resolve(na_single({
    single_door_panel_stile_width_mm       : 140,
    single_door_panel_top_rail_width_mm    : 120,
    single_door_panel_bottom_rail_width_mm : 260
})).leaves[0].panelLayout;
na_expect('Stile width drives the layout', fatStiles.stileMm, 140);
na_expect('Top rail width drives the layout', fatStiles.topRailMm, 120);
na_expect('Bottom rail width drives the layout', fatStiles.bottomRailMm, 260);
na_expect('Field region starts above the bottom rail',
    fatStiles.fieldRegion.zMm, resolvedSingle.leaves[0].originZMm + 260);

const tallField = Single.na_resolve(na_single({
    single_door_fielded_section_height_mm : 800,
    single_door_mid_rail_width_mm         : 200
})).leaves[0].panelLayout;
na_expect('Fielded section height honoured', tallField.fieldRegion.heightMm, 800);
na_expect('Mid rail width honoured', tallField.midRailMm, 200);
na_expect('Glazed region starts above field + midrail',
    tallField.glazedRegion.zMm, tallField.fieldRegion.zMm + 800 + 200);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 4 - Single and Double Agree Leaf-for-Leaf
// -----------------------------------------------------------------------------
// Give the double door two leaves the same width as the single door's one
// leaf and the same panel settings; the shared resolver must produce the same
// panel layout, measured relative to each leaf's own origin.

na_suite('Suite 4 | Cross-product panel parity');

const NA_SHARED_PANEL = {
    leaf_composition             : 'GlazedOverFielded',
    panel_output_mode            : 'ThreeDimensional',
    panel_profile                : 'RaisedBevelled',
    panel_preset                 : 'FourPanel',
    fielded_section_height_mm    : 520,
    mid_rail_width_mm            : 140,
    panel_stile_width_mm         : 110,
    panel_top_rail_width_mm      : 105,
    panel_bottom_rail_width_mm   : 230,
    panel_inset_mm               : 30,
    panel_depth_mm               : 14,
    panel_bevel_width_mm         : 20,
    leaf_thickness_mm            : 54
};

// HELPER FUNCTION | Expand Shared Panel Settings Under One Product Prefix
// ------------------------------------------------------------
function na_prefixed(prefix) {
    const out = {};
    Object.keys(NA_SHARED_PANEL).forEach((suffix) => {
        out[prefix + '_' + suffix] = NA_SHARED_PANEL[suffix];
    });
    return out;
}
// ---------------------------------------------------------------

// 900mm clear leaf on the single door; a 1900mm double door with 50mm reveals
// gives an 1800mm clear width, so an EQ split is two 900mm leaves.
const paritySingle = Single.na_resolve(na_single(na_prefixed('single_door'))).leaves[0];
const parityDouble = Double.na_resolve(na_double(Object.assign(
    { double_door_active_leaf_width_mm: 'EQ' },
    na_prefixed('double_door')
))).leaves[0];

na_expect('Both leaves are 900mm wide', [paritySingle.widthMm, parityDouble.widthMm], [900, 900]);

// HELPER FUNCTION | Re-Base a Panel Layout onto its Own Leaf Origin
// ------------------------------------------------------------
function na_relative(leaf) {
    const layout = leaf.panelLayout;
    const rebase = (region) => region && {
        x : Math.round((region.xMm - leaf.originXMm) * 1000) / 1000,
        z : Math.round((region.zMm - leaf.originZMm) * 1000) / 1000,
        w : Math.round(region.widthMm * 1000) / 1000,
        h : Math.round(region.heightMm * 1000) / 1000
    };
    return {
        stile      : layout.stileMm,
        topRail    : layout.topRailMm,
        bottomRail : layout.bottomRailMm,
        midRail    : layout.midRailMm,
        field      : rebase(layout.fieldRegion),
        glazed     : rebase(layout.glazedRegion),
        cells      : layout.fieldCells.map(rebase),
        dividers   : layout.fieldDividers.map(rebase)
    };
}
// ---------------------------------------------------------------

na_expect('Panel layouts are identical leaf-for-leaf',
    na_relative(paritySingle), na_relative(parityDouble));

na_expect('Leaf thickness is identical',
    paritySingle.thicknessMm, parityDouble.thicknessMm);

['composition', 'outputMode', 'profile', 'preset', 'insetMm', 'depthMm', 'bevelMm',
 'horizontalBars', 'verticalBars', 'glazeBarWidthMm', 'glazeBarInsetMm'].forEach((key) => {
    na_expect('Effective setting ' + key + ' matches',
        paritySingle.settings[key], parityDouble.settings[key]);
});

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 5 - The Elevation Draws a Door, Not a Window
// -----------------------------------------------------------------------------

na_suite('Suite 5 | Single-door elevation output');

const SingleElevation = window.Na__ExtSingleDoor__ElevationGenerator;

const fieldedNodes = na_render_elevation(SingleElevation, na_single({
    single_door_leaf_composition : 'FullyFielded',
    single_door_panel_preset     : 'SixPanel'
}));
const glazedNodes = na_render_elevation(SingleElevation, na_single({
    single_door_leaf_composition : 'FullyGlazed'
}));

// HELPER FUNCTION | Count Rects Painted with the Glazing Tint
// ------------------------------------------------------------
function na_glass_rects(nodes) {
    return nodes.filter((node) => node.tag === 'rect' && node.attrs.fill === '#b9dcea').length;
}
// ---------------------------------------------------------------

na_assert('FullyFielded elevation paints no glazing', na_glass_rects(fieldedNodes) === 0);
na_assert('FullyGlazed elevation paints glazing', na_glass_rects(glazedNodes) > 0);

na_assert('Elevation emits glazebar click targets',
    glazedNodes.some((node) => node.attrs.class === 'na-glazebar-click-target'));

na_assert('Elevation draws the handle circle',
    glazedNodes.some((node) => node.tag === 'circle'));
na_assert('Fixed panels drop the handle',
    na_render_elevation(SingleElevation, na_single({ single_door_fixed_panels: true }))
        .every((node) => node.tag !== 'circle'));

// The composition change must move real geometry, not just a config key.
const onePanelNodes  = na_render_elevation(SingleElevation, na_single({
    single_door_leaf_composition : 'FullyFielded',
    single_door_panel_preset     : 'OnePanel'
}));
na_assert('SixPanel draws more rects than OnePanel',
    fieldedNodes.filter((n) => n.tag === 'rect').length >
    onePanelNodes.filter((n) => n.tag === 'rect').length);

const dimensionText = glazedNodes.filter((node) => node.tag === 'text').map((node) => node.textContent);
na_assert('Elevation labels the overall size',
    dimensionText.some((text) => text.indexOf('W: 1000mm') === 0));
na_assert('Elevation labels the leaf width',
    dimensionText.some((text) => text === 'Left: 900mm'));

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 6 - Plan View and DXF
// -----------------------------------------------------------------------------

na_suite('Suite 6 | Single-door plan and DXF');

const planRoot = na_make_node('svg');
window.Na__ExtSingleDoor__PlanGenerator.na_render(planRoot, na_single());
const planNodes = na_flatten(planRoot);

na_assert('Plan draws the leaf footprint',
    planNodes.some((node) => node.tag === 'polygon'));
na_assert('Plan draws the swing arc',
    planNodes.some((node) => node.tag === 'polyline'));
na_assert('Plan draws the hinge pivot',
    planNodes.some((node) => node.tag === 'circle' && node.attrs.fill === '#d00000'));

const fixedPlanRoot = na_make_node('svg');
window.Na__ExtSingleDoor__PlanGenerator.na_render(
    fixedPlanRoot, na_single({ single_door_fixed_panels: true })
);
const fixedPlanNodes = na_flatten(fixedPlanRoot);
na_assert('Fixed panel plan drops the swing arc',
    fixedPlanNodes.every((node) => node.tag !== 'polyline'));
na_assert('Fixed panel plan drops the hinge pivot',
    fixedPlanNodes.every((node) => !(node.tag === 'circle' && node.attrs.fill === '#d00000')));

const dxf = window.Na__ExtSingleDoor__DxfExporter.na_export_dxf(na_single());
na_assert('DXF opens an ENTITIES section', dxf.indexOf('0\nSECTION\n2\nENTITIES\n') === 0);
na_assert('DXF terminates cleanly', dxf.indexOf('0\nENDSEC\n0\nEOF\n') > 0);
['NA_FRAME', 'NA_DOOR_LEAF', 'NA_RAIL_STILE', 'NA_DOOR_PANEL', 'NA_GLASS',
 'NA_DOOR_HARDWARE', 'NA_DOOR_SWING'].forEach((layer) => {
    na_assert('DXF emits layer ' + layer, dxf.indexOf(layer) > 0);
});
na_assert('DXF titles the single door',
    dxf.indexOf('Exterior Single Door 1000 x 2100 mm') > 0);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 7 - Validation
// -----------------------------------------------------------------------------

na_suite('Suite 7 | Single-door validation');

na_assert('A sensible door validates',
    Single.na_validate(na_single()).valid === true);

const tooNarrow = Single.na_validate(na_single({ width_mm: 340 }));
na_assert('A sub-300mm clear leaf is rejected', tooNarrow.valid === false);
na_assert('The rejection names the 300mm leaf',
    tooNarrow.errors.some((message) => message.indexOf('300 mm leaf') > 0));

// The double door's own floor must not have moved.
na_assert('Double door still validates at 1900mm',
    Double.na_validate(na_double()).valid === true);
// 600mm overall minus two 50mm reveals leaves 500mm clear - short of the two
// 300mm leaves a pair needs.
na_assert('Double door still rejects a 600mm opening',
    Double.na_validate(na_double({ width_mm: 600 })).valid === false);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 8 - Double-Door Behaviour Is Unchanged by the Extraction
// -----------------------------------------------------------------------------

na_suite('Suite 8 | Double-door regression guard');

const doubleResolved = Double.na_resolve(na_double());
na_expect('Two leaves resolved', doubleResolved.leaves.length, 2);
na_expect('EQ splits the clear width evenly',
    [doubleResolved.leaves[0].widthMm, doubleResolved.leaves[1].widthMm], [900, 900]);

const weighted = Double.na_resolve(na_double({
    double_door_active_leaf       : 'Left',
    double_door_active_leaf_width_mm: 1100
}));
na_expect('An absolute active width is honoured',
    [weighted.leaves[0].widthMm, weighted.leaves[1].widthMm], [1100, 700]);

const clamped = Double.na_resolve(na_double({
    double_door_active_leaf_width_mm: 1750
}));
na_expect('Active width is clamped so the passive leaf keeps 300mm',
    [clamped.leaves[0].widthMm, clamped.leaves[1].widthMm], [1500, 300]);

// Per-leaf overrides are double-door-only and must survive the extraction.
const overridden = Double.na_resolve(na_double({
    double_door_leaf_settings_linked      : false,
    double_door_right_leaf_override_enabled: true,
    double_door_right_leaf_composition    : 'FullyGlazed'
}));
na_expect('Linked leaf keeps the shared composition',
    overridden.leaves[0].settings.composition, 'GlazedOverFielded');
na_expect('Overridden leaf takes its own composition',
    overridden.leaves[1].settings.composition, 'FullyGlazed');

const seeded = Double.na_seed_leaf_override(na_double(), 'left');
na_assert('Seeding enables the override flag',
    seeded.double_door_left_leaf_override_enabled === true);
na_expect('Seeding copies the effective composition',
    seeded.double_door_left_leaf_composition, 'GlazedOverFielded');

na_expect('Double-door DXF still titles itself',
    window.Na__ExtDouble__DxfExporter.na_export_dxf(na_double())
        .indexOf('Exterior Double Door 1900 x 2100 mm') > 0,
    true);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 9 - Glaze Bar Positions Match Between Products
// -----------------------------------------------------------------------------

na_suite('Suite 9 | Glaze bar parity');

const barSingle = Single.na_resolve(na_single(Object.assign(
    { horizontal_glaze_bars: 3, vertical_glaze_bars: 2 },
    na_prefixed('single_door')
))).leaves[0];
const barDouble = Double.na_resolve(na_double(Object.assign(
    { horizontal_glaze_bars: 3, vertical_glaze_bars: 2,
      double_door_active_leaf_width_mm: 'EQ' },
    na_prefixed('double_door')
))).leaves[0];

na_expect('Bar counts agree',
    [barSingle.settings.horizontalBars, barSingle.settings.verticalBars],
    [barDouble.settings.horizontalBars, barDouble.settings.verticalBars]);

const Shared = window.Na__ExtDoorCommon__ElevationGenerator;
const singleBars = Shared.na_final_bar_positions(barSingle, barSingle.panelLayout.glazedRegion);
const doubleBars = Shared.na_final_bar_positions(barDouble, barDouble.panelLayout.glazedRegion);

na_expect('Horizontal bar count matches', singleBars.horizontal.length, 3);
na_expect('Vertical bar count matches', singleBars.vertical.length, 2);
singleBars.vertical.forEach((position, index) => {
    na_close('Vertical bar ' + (index + 1) + ' sits at the same leaf-relative x',
        position - barSingle.originXMm, doubleBars.vertical[index] - barDouble.originXMm);
});
singleBars.horizontal.forEach((position, index) => {
    na_close('Horizontal bar ' + (index + 1) + ' sits at the same z',
        position, doubleBars.horizontal[index]);
});

na_expect('Glazebar removal keys use panel index 0 on a single door',
    Shared.na_glazebar_key(barSingle, 'vertical', 1), '0:0:0:0:vertical:1');

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Summary
// -----------------------------------------------------------------------------

console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
