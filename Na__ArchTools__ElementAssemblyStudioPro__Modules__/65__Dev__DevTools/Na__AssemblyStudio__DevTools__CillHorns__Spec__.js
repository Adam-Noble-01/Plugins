/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - CILL HORNS SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__CillHorns__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for V2.4.0 - cill horns on windows and all
                four exterior door types.
   CREATED    : 02-Nov-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__CillHorns__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   The horns run past each reveal in front of the wall face, so in elevation
   the cill is simply wider than the frame by the horn at each end. The frame
   itself, and every dimension, stays where it was.

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

const NA_LAYOUTS = {};
global.window   = global;
global.document = {
    createElementNS  : (ns, tag) => na_make_node(tag),
    createElement    : () => ({ appendChild: () => {} }),
    getElementById   : (id) => (String(id).indexOf('na-controls-') === 0 ? { innerHTML: '', insertAdjacentHTML: () => {} } : null),
    querySelector    : () => null,
    querySelectorAll : () => [],
    addEventListener : () => {}
};
window.Na__Ui__Controls      = { na_createControl: () => '' };
window.Na__Ui__Events        = { na_attachEventListeners: () => {} };
window.Na__Ui__SectionLayout = { na_register: (tabId, spec) => { NA_LAYOUTS[tabId] = spec; } };
const na_console_error = console.error;
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
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__LayoutMap__.js',
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

const Horn = window.Na__Viewport__SvgGenerator.na_cillHornLengthMm;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Helpers
// -----------------------------------------------------------------------------

const NA_CILL_COLOUR = '#A0908A';

// HELPER FUNCTION | The Cill Rectangle of an SVG String
// ------------------------------------------------------------
function na_cill_rect(svg) {
    const match = new RegExp('<rect x="([^"]+)" y="([^"]+)" width="([^"]+)" height="([^"]+)"\\s+fill="' + NA_CILL_COLOUR + '"').exec(svg);
    return match ? { x: Number(match[1]), y: Number(match[2]), width: Number(match[3]), height: Number(match[4]) } : null;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | A Whole Window Config With the Dialog's Own Defaults
// ------------------------------------------------------------
function na_window(overrides) {
    return Object.assign({}, Ui.na_getConfig(), {
        width_mm: 1800, height_mm: 1200, frame_thickness_mm: 50, advanced_frame_controls: false, mullions: 0, transoms: 0,
        has_cill: true, cill_height_mm: 50, cill_depth_mm: 50, show_dimensions: false, cill_horns_enabled: false,
        window_board_enabled: false, multifold_mode: false, sliding_mode: false
    }, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | A Hinged Door Config Seeded From Its Own Controls
// ------------------------------------------------------------
function na_hinged(prefix, array, modeKey, overrides) {
    const seeded = {};
    window[array].forEach((item) => {
        if (item && typeof item.id === 'string' && item.id.indexOf(prefix) === 0) seeded[item.id] = item.default;
    });
    const config = { width_mm: 1000, height_mm: 2100, frame_thickness_mm: 50, frame_depth_mm: 70,
                     frame_wall_inset_mm: 0, has_cill: true, cill_height_mm: 50, cill_depth_mm: 50,
                     show_dimensions: false, horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25, glazebar_inset_mm: 10 };
    config[modeKey] = true;
    return Object.assign(config, seeded, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | The Cill Rectangle of a Rendered Hinged Door
// ------------------------------------------------------------
function na_hinged_cill(generator, config) {
    const root = na_make_node('svg');
    generator.na_render(root, config);
    const nodes = na_flatten(root).filter(node => node.tag === 'rect');
    const padding = 180;
    const cill = nodes.filter(node => Number(node.attrs.y) === padding + config.height_mm && Number(node.attrs.height) === config.cill_height_mm);
    return { count: cill.length, x: cill.length ? Number(cill[0].attrs.x) : null, width: cill.length ? Number(cill[0].attrs.width) : null,
             others: nodes.filter(node => cill.indexOf(node) === -1).map(node => [node.attrs.x, node.attrs.y, node.attrs.width, node.attrs.height]) };
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Bounding Box of One Layer's Lines in DXF Text
// ------------------------------------------------------------
function na_dxf_box(dxf, layer) {
    const lines = dxf.split('\n').map(line => line.trim());
    const xs = [];
    const ys = [];
    let current = null;
    for (let i = 0; i + 1 < lines.length; i += 2) {
        const code = lines[i];
        const value = lines[i + 1];
        if (code === '0') current = null;
        else if (code === '8') current = value;
        else if (current === layer && (code === '10' || code === '11')) xs.push(Number(value));
        else if (current === layer && (code === '20' || code === '21')) ys.push(Number(value));
    }
    return xs.length ? [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)] : null;
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Controls and Layout
// -----------------------------------------------------------------------------

na_suite('Controls');
const na_control = id => window.NA_CILL_FRAME_CONFIG.find(item => item.id === id);
na_expect('the switch is off by default', [na_control('cill_horns_enabled').type, na_control('cill_horns_enabled').default], ['toggle', false]);
na_expect('Horn Length Past Reveal', [na_control('cill_horn_length_mm').label, na_control('cill_horn_length_mm').default, na_control('cill_horn_length_mm').min], ['Horn Length Past Reveal', 40, 5]);
na_expect('Horn Let Into Wall stops at the wall face by default', [na_control('cill_horn_let_in_mm').label, na_control('cill_horn_let_in_mm').default, na_control('cill_horn_let_in_mm').min], ['Horn Let Into Wall', 0, 0]);
na_expect('the longest horn stays inside the 180 preview padding', na_control('cill_horn_length_mm').max < 180, true);
na_expect('no dashes in the labels', ['cill_horns_enabled', 'cill_horn_length_mm', 'cill_horn_let_in_mm'].filter(id => /[-–—]/.test(na_control(id).label)), []);

na_suite('Sits in the Cill group');
const na_frame = NA_LAYOUTS.windows.sections.find(section => section.key === 'frame');
const na_item = id => na_frame.items.find(item => item.id === id);
['cill_horns_enabled', 'cill_horn_length_mm', 'cill_horn_let_in_mm'].forEach((id) => {
    na_expect(id + ' is under Cill, at the same tier', [na_item(id).group, na_item(id).tier], ['Cill', na_item('cill_height_mm').tier]);
    na_expect(id + ' on every product', na_item(id).products, undefined);
});
na_expect('the switch shows with the cill', [na_item('cill_horns_enabled').showIf({ has_cill: true }), na_item('cill_horns_enabled').showIf({ has_cill: false })], [true, false]);
['cill_horn_length_mm', 'cill_horn_let_in_mm'].forEach((id) => {
    na_expect(id + ' appears only when switched on', [
        na_item(id).showIf({ has_cill: true, cill_horns_enabled: true }),
        na_item(id).showIf({ has_cill: true, cill_horns_enabled: false }),
        na_item(id).showIf({ has_cill: true }),
        na_item(id).showIf({ has_cill: false, cill_horns_enabled: true })
    ], [true, false, false, false]);
    na_expect(id + ' search can switch both on', na_item(id).need.fix, [['has_cill', true], ['cill_horns_enabled', true]]);
});
na_expect('the section summary says so', na_frame.summary({ frame_thickness_mm: 50, frame_wall_inset_mm: 0, cill_height_mm: 50, cill_horns_enabled: true }, 'casement').indexOf('cill 50 with horns') >= 0, true);
na_expect('and not when off', na_frame.summary({ frame_thickness_mm: 50, frame_wall_inset_mm: 0, cill_height_mm: 50 }, 'casement').indexOf('horns'), -1);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Length Rule
// -----------------------------------------------------------------------------

na_suite('How far past each reveal');
na_expect('nothing in the config', Horn({}), 0);
na_expect('switched off', Horn({ cill_horns_enabled: false, cill_horn_length_mm: 75 }), 0);
na_expect('on, default length', Horn({ cill_horns_enabled: true }), 40);
na_expect('on, its own length', Horn({ cill_horns_enabled: true, cill_horn_length_mm: 75 }), 75);
na_expect('zero length', Horn({ cill_horns_enabled: true, cill_horn_length_mm: 0 }), 0);
na_expect('a flush cill has nothing in front of the wall', Horn({ cill_horns_enabled: true, cill_depth_mm: 0 }), 0);
na_expect('nor a cill set back into the reveal', Horn({ cill_horns_enabled: true, cill_depth_mm: -50, cill_horn_length_mm: 40 }), 0);
na_expect('a flush cill let into the wall has', Horn({ cill_horns_enabled: true, cill_depth_mm: 0, cill_horn_let_in_mm: 30 }), 40);
na_expect('let in less than it is set back: still none', Horn({ cill_horns_enabled: true, cill_depth_mm: -50, cill_horn_let_in_mm: 30 }), 0);
na_expect('let in further than it is set back', Horn({ cill_horns_enabled: true, cill_depth_mm: -20, cill_horn_let_in_mm: 50 }), 40);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Previews
// -----------------------------------------------------------------------------

na_suite('Window preview');
const Gen = window.Na__Viewport__SvgGenerator;
const na_window_svg = cfg => Gen.na_generateWindowSvg(cfg);
const na_w_off = na_window_svg(na_window());
const na_w_on = na_window_svg(na_window({ cill_horns_enabled: true, cill_horn_length_mm: 40 }));
na_expect('off: frame width', na_cill_rect(na_w_off), { x: 0, y: 0, width: 1800, height: 50 });
na_expect('on: 40 past each side, same height', na_cill_rect(na_w_on), { x: -40, y: 0, width: 1880, height: 50 });
na_expect('nothing else in the drawing moves', na_w_on.replace(/<rect x="[^"]+" y="[^"]+" width="[^"]+" height="[^"]+"\s+fill="#A0908A"/, ''),
          na_w_off.replace(/<rect x="[^"]+" y="[^"]+" width="[^"]+" height="[^"]+"\s+fill="#A0908A"/, ''));
na_expect('a set back stub cill stays frame width', na_cill_rect(na_window_svg(na_window({ cill_horns_enabled: true, cill_depth_mm: -50 }))).width, 1800);
na_expect('no cill, no horns', na_cill_rect(na_window_svg(na_window({ has_cill: false, cill_horns_enabled: true }))), null);
na_expect('no bottom frame, no horns', na_cill_rect(na_window_svg(na_window({ advanced_frame_controls: true, frame_top_thickness_mm: 50, frame_left_thickness_mm: 50, frame_right_thickness_mm: 50, frame_bottom_thickness_mm: 0, cill_horns_enabled: true }))), null);

[
    ['Single door preview', 'single_door_', 'NA_EXT_SINGLE_DOOR_CONFIG', 'ext_single_door_mode', window.Na__ExtSingleDoor__ElevationGenerator],
    ['Double door preview', 'double_door_', 'NA_DOUBLE_DOOR_CONFIG', 'ext_double_door_mode', window.Na__ExtDouble__ElevationGenerator]
].forEach(([title, prefix, array, mode, generator]) => {
    na_suite(title);
    const off = na_hinged_cill(generator, na_hinged(prefix, array, mode));
    const on = na_hinged_cill(generator, na_hinged(prefix, array, mode, { cill_horns_enabled: true, cill_horn_length_mm: 60 }));
    na_expect('off: frame width, under the opening', [off.count, off.x, off.width], [1, 180, 1000]);
    na_expect('on: 60 past each side', [on.count, on.x, on.width], [1, 120, 1120]);
    na_expect('nothing else moves', on.others, off.others);
});

[
    ['Sliding door preview', cfg => window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg(cfg), { sliding_mode: true }],
    ['Bifold door preview', cfg => window.Na__ExtFold__ElevationGenerator.na_generate_bifold_svg(cfg), { multifold_mode: true }]
].forEach(([title, generate, mode]) => {
    na_suite(title);
    const set = Object.assign({ width_mm: 3000, height_mm: 2100, frame_thickness_mm: 50, has_cill: true, cill_height_mm: 50, cill_depth_mm: 50,
                                show_dimensions: false, horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25 }, mode);
    const off = na_cill_rect(generate(set));
    const on = na_cill_rect(generate(Object.assign({}, set, { cill_horns_enabled: true, cill_horn_length_mm: 60 })));
    na_expect('off: opening width', [off.x, off.width, off.height], [0, 3000, 50]);
    na_expect('on: 60 past each side', [on.x, on.width, on.height], [-60, 3120, 50]);
    const stub = na_cill_rect(generate(Object.assign({}, set, { cill_horns_enabled: true, cill_depth_mm: -20 })));
    na_expect('set back: opening width', [stub.x, stub.width], [0, 3000]);
});

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Door DXF
// -----------------------------------------------------------------------------

na_suite('Hinged door DXF');
const na_dxf_door = overrides => window.Na__ExtSingleDoor__DxfExporter.na_export_dxf(na_hinged('single_door_', 'NA_EXT_SINGLE_DOOR_CONFIG', 'ext_single_door_mode', overrides));
const na_dxf_off = na_dxf_door();
const na_dxf_on = na_dxf_door({ cill_horns_enabled: true, cill_horn_length_mm: 60 });
na_expect('off: frame width, sitting at the floor', na_dxf_box(na_dxf_off, 'NA_CILL'), [0, 1000, 0, 50]);
na_expect('on: 60 past each side', na_dxf_box(na_dxf_on, 'NA_CILL'), [-60, 1060, 0, 50]);
na_expect('the frame stays', na_dxf_box(na_dxf_on, 'NA_FRAME'), na_dxf_box(na_dxf_off, 'NA_FRAME'));

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Saved Elements
// -----------------------------------------------------------------------------

na_suite('Older elements and partial updates');
Ui.na_setConfig({ cill_horns_enabled: true, cill_horn_length_mm: 75 });
na_expect('a partial update leaves the switch', Ui.na_getConfig().cill_horns_enabled, true);
Ui.na_setConfig({ width_mm: 1500 }, { fullConfig: true });
na_expect('an element saved before V2.4.0 does not take on the last one\'s horns', Ui.na_getConfig().cill_horns_enabled, false);
Ui.na_setConfig({ width_mm: 1500, cill_horns_enabled: true, cill_horn_length_mm: 75 }, { fullConfig: true });
na_expect('one saved with horns keeps them', [Ui.na_getConfig().cill_horns_enabled, Ui.na_getConfig().cill_horn_length_mm], [true, 75]);

na_suite('Ruby side agrees');
const na_read = relative => fs.readFileSync(path.join(NA_MODULES, relative), 'utf8');
const na_defaults = na_read('20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Defaults__.rb');
na_expect('default config: off', /"cill_horns_enabled"\s*:\s*false/.test(na_defaults), true);
na_expect('default config: same length as the slider', new RegExp('"cill_horn_length_mm"\\s*:\\s*' + na_control('cill_horn_length_mm').default + '\\b').test(na_defaults), true);
na_expect('default config: same let in as the slider', new RegExp('"cill_horn_let_in_mm"\\s*:\\s*' + na_control('cill_horn_let_in_mm').default + '\\b').test(na_defaults), true);
const na_shared = /NA_DOOR_SHARED_WINDOW_KEYS = \[([\s\S]*?)\n\s*\]/.exec(na_read('20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__DialogCallbacks__.rb'))[1];
na_expect('sliding and bifold doors save all three', ['cill_horns_enabled', 'cill_horn_length_mm', 'cill_horn_let_in_mm'].filter(key => na_shared.indexOf('"' + key + '"') === -1), []);
[
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__AssemblyComposer__.rb',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__AssemblyComposer__.rb',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__AssemblyComposer__.rb',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__AssemblyComposer__.rb',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__GeometryEngine__.rb'
].forEach((relative) => {
    na_expect(path.basename(relative) + ' asks for the horns', na_read(relative).indexOf('na_cill_horns(') >= 0, true);
});

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);
