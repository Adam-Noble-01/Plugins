/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - ARCHED HEADER RAIL SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__ArchedHeader__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for V2.5.2 - arched header rails on window
                casements and all four exterior door types.
   CREATED    : 03-Nov-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__ArchedHeader__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   The rule under test: the crown of the arc sits where the flat glass top was,
   so the rail keeps its set depth at the centre, and the arc falls away from
   there by the Arch Height. A true arch makes a special head across the full
   width, on stiles that stop at the springing line.

   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');


// -----------------------------------------------------------------------------
// REGION | Harness
// -----------------------------------------------------------------------------

const NA_MODULES = path.resolve(__dirname, '..', '02__Src__AppModules');
const NA_ROOT    = path.resolve(__dirname, '..');

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

// HELPER FUNCTION | Round to a Tenth of a Millimetre, for Comparing Sums
// ------------------------------------------------------------
function na_r(value) {
    return Math.round(value * 10) / 10;
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

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Stub and Shipped Modules
// -----------------------------------------------------------------------------

const NA_LAYOUTS = {};
const NA_ELEMENTS = {};                                             // <-- Sliders and controls the suite reads back
const na_element = id => (NA_ELEMENTS[id] = NA_ELEMENTS[id] || { id: id, style: {}, max: '', value: '' });

global.window   = global;
global.document = {
    createElementNS  : (ns, tag) => na_make_node(tag),
    createElement    : () => ({ appendChild: () => {} }),
    getElementById   : (id) => {
        if (String(id).indexOf('na-controls-') === 0) return { innerHTML: '', insertAdjacentHTML: () => {} };
        return /arched_header_height_mm-(slider|input)$/.test(String(id)) ? na_element(id) : null;
    },
    querySelector    : (selector) => {
        const match = /data-control-id="([^"]*arched_header_height_mm)"/.exec(String(selector));
        return match ? na_element(match[1]) : null;
    },
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
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__ArchMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Export__Dxf__.js',
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

const Arch = window.Na__ArchMath;
const Gen  = window.Na__Viewport__SvgGenerator;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Helpers
// -----------------------------------------------------------------------------

// HELPER FUNCTION | A Whole Window Config With the Dialog's Own Defaults
// ------------------------------------------------------------
// One 900 x 1200 casement in a 50 frame: panel x 50..850, z 50..1150, 65 stiles
// and rails, so the glass is 670 wide from x 115, z 115 up to 1085.
function na_window(overrides) {
    return Object.assign({}, Ui.na_getConfig(), {
        width_mm: 900, height_mm: 1200, frame_thickness_mm: 50, advanced_frame_controls: false, mullions: 0, transoms: 0,
        casement_width_mm: 65, casement_sizes_individual: false, casements_per_opening: 1, show_casements: true,
        sliding_sash_window: false, double_door_mode: false, ext_single_door_mode: false, multifold_mode: false, sliding_mode: false,
        has_cill: true, cill_height_mm: 50, show_dimensions: false, cill_horns_enabled: false, window_board_enabled: false,
        horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25, leaded_glass_enabled: false,
        removed_casements: [], removed_transom_segments: [], removed_glazebars: [], casement_overrides: {},
        arched_header_enabled: false, arched_header_height_mm: 60, arched_header_true_arch: false, arched_header_segments: '12'
    }, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | The Same Window With the Arched Header Rail On
// ------------------------------------------------------------
function na_arched(overrides) {
    return na_window(Object.assign({ arched_header_enabled: true }, overrides || {}));
}
// ---------------------------------------------------------------

// HELPER FUNCTION | A Hinged Door Config Seeded From Its Own Controls
// ------------------------------------------------------------
function na_hinged(prefix, array, modeKey, overrides) {
    const seeded = {};
    const seed = (item) => {
        if (!item || typeof item.id !== 'string') return;
        if (item.id.indexOf(prefix) === 0) seeded[item.id] = item.default;
        if (Array.isArray(item.children)) item.children.forEach(seed);
    };
    window[array].forEach(seed);
    const config = { width_mm: 1000, height_mm: 2100, frame_thickness_mm: 50, frame_depth_mm: 70,
                     frame_wall_inset_mm: 0, has_cill: true, cill_height_mm: 50, cill_depth_mm: 50,
                     show_dimensions: false, horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25, glazebar_inset_mm: 10 };
    config[modeKey] = true;
    return Object.assign(config, seeded, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Every Polygon in an SVG String, as [[x, y up] ...]
// ------------------------------------------------------------
function na_polygons(svg, fill) {
    const found = [];
    const pattern = /<polygon points="([^"]+)" fill="([^"]+)"/g;
    let match = pattern.exec(svg);
    while (match) {
        if (!fill || match[2] === fill) {
            found.push(match[1].split(' ').map(pair => pair.split(',').map(Number)).map(([x, y]) => [x, -y]));
        }
        match = pattern.exec(svg);
    }
    return found;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Bounding Box of Point Pairs
// ------------------------------------------------------------
function na_box(points) {
    const xs = points.map(point => point[0]);
    const zs = points.map(point => point[1]);
    return [na_r(Math.min(...xs)), na_r(Math.max(...xs)), na_r(Math.min(...zs)), na_r(Math.max(...zs))];
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Rectangles of an SVG String That Draw the Casement Stiles
// ------------------------------------------------------------
function na_rect_list(svg) {
    const found = [];
    const pattern = /<rect x="([^"]+)" y="([^"]+)" width="([^"]+)" height="([^"]+)"/g;
    let match = pattern.exec(svg);
    while (match) {
        found.push({ x: Number(match[1]), top: -Number(match[2]), width: Number(match[3]), height: Number(match[4]) });
        match = pattern.exec(svg);
    }
    return found;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Lines of One Layer in DXF Text, as [x1, y1, x2, y2]
// ------------------------------------------------------------
function na_dxf_lines(dxf, layer) {
    const rows = dxf.split('\n').map(row => row.trim());
    const lines = [];
    for (let i = 0; i + 1 < rows.length; i += 1) {
        if (rows[i] !== '0' || rows[i + 1] !== 'LINE') continue;
        const line = {};
        let j = i + 2;
        while (j + 1 < rows.length && rows[j] !== '0') {
            line[rows[j]] = rows[j + 1];
            j += 2;
        }
        if (layer === null || line['8'] === layer) lines.push([line['10'], line['20'], line['11'], line['21']].map(Number));
        i = j - 1;
    }
    return lines;
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | The Arc
// -----------------------------------------------------------------------------

na_suite('Reading the settings');
na_expect('nothing in the config', Arch.na_settings({}, ''), null);
na_expect('switched off', Arch.na_settings({ arched_header_enabled: false, arched_header_height_mm: 90 }, ''), null);
na_expect('on: the defaults', Arch.na_settings({ arched_header_enabled: true }, ''), { riseMm: 60, trueArch: false, segments: 12 });
na_expect('a door reads its own keys', Arch.na_settings({ arched_header_enabled: true, single_door_arched_header_enabled: false }, 'single_door_'), null);
na_expect('segments arrive as text from the select', Arch.na_settings({ arched_header_enabled: true, arched_header_segments: '48' }, '').segments, 48);
na_expect('an unknown segment count falls back to 12', Arch.na_settings({ arched_header_enabled: true, arched_header_segments: '7' }, '').segments, 12);
na_expect('the rise floor is 20', Arch.na_settings({ arched_header_enabled: true, arched_header_height_mm: 5 }, '').riseMm, 20);

na_suite('A slight segmental arc');
const na_slight = Arch.na_resolve({ riseMm: 60, trueArch: false, segments: 12 }, 100, 200, 800, 1000);
na_expect('the crown stays at the flat glass top', na_slight.crownZ, 1200);
na_expect('it springs the arch height below', na_slight.springingZ, 1140);
na_expect('radius from span and rise', na_r(na_slight.radius), 1363.3);
na_expect('13 points for 12 segments', na_slight.points.length, 13);
na_expect('it starts on the left stile', na_slight.points[0], [100, 1140]);
na_expect('it ends on the right stile', na_slight.points[12], [900, 1140]);
na_expect('the middle point is the crown itself', [na_r(na_slight.points[6][0]), na_r(na_slight.points[6][1])], [500, 1200]);
na_expect('every point is on the circle', na_slight.points.every(([x, z]) => Math.abs(Math.hypot(x - na_slight.centreX, z - na_slight.centreZ) - na_slight.radius) < 1e-6), true);
na_expect('it is not a true arch', na_slight.trueArch, false);
na_expect('24 segments, 25 points', Arch.na_resolve({ riseMm: 60, trueArch: false, segments: 24 }, 0, 0, 800, 1000).points.length, 25);
na_expect('48 segments, 49 points', Arch.na_resolve({ riseMm: 60, trueArch: false, segments: 48 }, 0, 0, 800, 1000).points.length, 49);

na_suite('A true arch');
const na_true = Arch.na_resolve({ riseMm: 60, trueArch: true, segments: 12 }, 100, 200, 800, 1000);
na_expect('the switch sets the rise to half the width', [na_true.rise, na_true.radius, na_true.trueArch], [400, 400, true]);
na_expect('a rise of half the width is one too', Arch.na_resolve({ riseMm: 400, trueArch: false, segments: 12 }, 100, 200, 800, 1000).trueArch, true);
na_expect('a rise taller than that holds at it', Arch.na_resolve({ riseMm: 900, trueArch: false, segments: 12 }, 100, 200, 800, 1000).rise, 400);
na_expect('just under stays segmental', Arch.na_resolve({ riseMm: 399, trueArch: false, segments: 12 }, 100, 200, 800, 1000).trueArch, false);
const na_first_chord = [na_true.points[1][0] - na_true.points[0][0], na_true.points[1][1] - na_true.points[0][1]];
na_expect('it leaves the stile near vertical (7.5 degrees at 12 segments)', na_r(Math.atan2(na_first_chord[0], na_first_chord[1]) * 180 / Math.PI), 7.5);

na_suite('Short and narrow glass');
const na_short = Arch.na_resolve({ riseMm: 300, trueArch: false, segments: 12 }, 0, 0, 800, 100);
na_expect('keeps 20 of glass at each side', [na_short.rise, na_short.springingZ], [80, 20]);
const na_short_true = Arch.na_resolve({ riseMm: 60, trueArch: true, segments: 12 }, 0, 0, 800, 100);
na_expect('True Arch on a short pane is the tallest arc that fits', [na_short_true.rise, na_short_true.trueArch], [80, false]);
na_expect('no room at all: flat', Arch.na_resolve({ riseMm: 60, trueArch: false, segments: 12 }, 0, 0, 800, 20), null);
na_expect('no glass: flat', Arch.na_resolve({ riseMm: 60, trueArch: false, segments: 12 }, 0, 0, 0, 500), null);
na_expect('no settings: flat', Arch.na_resolve(null, 0, 0, 800, 500), null);

na_suite('Where the slider tops out');
na_expect('half the widest glass', Arch.na_sliderMaxMm(770), 385);
na_expect('rounded up so its last stop reaches it', Arch.na_sliderMaxMm(773), 390);
na_expect('never under the floor', Arch.na_sliderMaxMm(10), 20);
na_expect('its last stop is a true arch', Arch.na_resolve({ riseMm: Arch.na_sliderMaxMm(773), trueArch: false, segments: 12 }, 0, 0, 773, 900).trueArch, true);

na_suite('Trimming members to the arch');
const na_t = na_slight;
na_expect('a bar at the centre runs to the crown', na_r(Arch.na_topOver(na_t, 480, 520)), 1200);
na_expect('off centre it takes its side nearest the crown', na_r(Arch.na_topOver(na_t, 200, 225)), na_r(na_t.centreZ + Math.sqrt(na_t.radius * na_t.radius - 275 * 275)));
na_expect('a vertical member stops at the arc', na_r(Arch.na_trimHeight(na_t, 200, 225, 200, 1000)), na_r(na_t.centreZ + Math.sqrt(na_t.radius * na_t.radius - 275 * 275) - 200));
na_expect('never taller than it was', Arch.na_trimHeight(na_t, 480, 520, 200, 500), 500);
na_expect('no arch: untouched', [Arch.na_trimHeight(null, 0, 10, 0, 500), Arch.na_trimRun(null, 5, 100, 50)], [500, [5, 100]]);
na_expect('below the springing a run is the full width', Arch.na_trimRun(na_t, 100, 800, 1100), [100, 800]);
const na_high_run = Arch.na_trimRun(na_t, 100, 800, 1180);
na_expect('above it the run narrows to the arc', [na_r(na_high_run[0] + na_high_run[1] / 2), na_high_run[1] < 800], [500, true]);
na_expect('above the crown there is nothing to build', Arch.na_trimRun(na_t, 100, 800, 1200), null);
const na_stile_true = Arch.na_trimHeight(na_true, 100, 110, 200, 1000);
na_expect('a bar hard against a true arch\'s stile barely rises past the springing', na_stile_true < 700, true);
na_expect('a bar outside the glass has no arc over it', Arch.na_topOver(na_true, 0, 50), na_true.springingZ);

na_suite('Stile height and outlines');
na_expect('segmental: stiles stay full height', Arch.na_stileHeight(na_slight, 100, 1165), 1165);
na_expect('true arch: they stop at the springing line', Arch.na_stileHeight(na_true, 100, 1165), 700);
na_expect('no arch: full height', Arch.na_stileHeight(null, 100, 1165), 1165);
const na_seg_head = Arch.na_headOutline(na_slight, 35, 965, 1265);
na_expect('segmental rail sits between the stiles, flat on top', na_box(na_seg_head), [100, 900, 1140, 1265]);
na_expect('the rail keeps its set depth at the crown', na_r(1265 - na_slight.points[6][1]), 65);
na_expect('segmental rail is the top edge plus the arc', na_seg_head.length, 15);
const na_true_head = Arch.na_headOutline(na_true, 35, 965, 1265);
na_expect('the true arch head spans the full width', na_box(na_true_head), [35, 965, 800, 1265]);
na_expect('and runs out over each stile', [na_true_head[2], na_true_head[na_true_head.length - 1]], [[965, 800], [35, 800]]);
na_expect('the glass: flat bottom, arched head', na_box(Arch.na_glassOutline(na_slight, 200)), [100, 900, 200, 1200]);
na_expect('glass is 2 bottom corners plus the arc', Arch.na_glassOutline(na_slight, 200).length, 15);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Controls and Layout
// -----------------------------------------------------------------------------

na_suite('Controls');
const na_find_control = (list, id) => {
    let found = null;
    const walk = items => items.forEach((item) => {
        if (item.id === id) found = item;
        if (Array.isArray(item.children)) walk(item.children);
    });
    walk(list);
    return found;
};
const na_arch_switch = na_find_control(window.NA_UI_CONFIG, 'arched_header_enabled');
na_expect('a switch that opens its options, off by default', [na_arch_switch.type, na_arch_switch.default, na_arch_switch.children.map(child => child.id)],
          ['expandable', false, ['arched_header_height_mm', 'arched_header_true_arch', 'arched_header_segments']]);
const na_height_control = na_find_control(window.NA_UI_CONFIG, 'arched_header_height_mm');
na_expect('Arch Height: min 20, default 60', [na_height_control.label, na_height_control.min, na_height_control.default, na_height_control.unit], ['Arch Height', 20, 60, 'mm']);
const na_segment_control = na_find_control(window.NA_UI_CONFIG, 'arched_header_segments');
na_expect('Arc Segments: 12 by default, or 24 or 48', [na_segment_control.default, na_segment_control.options.map(option => option.value)], ['12', ['12', '24', '48']]);
na_expect('no dashes in the labels', ['arched_header_enabled', 'arched_header_height_mm', 'arched_header_true_arch', 'arched_header_segments']
    .map(id => na_find_control(window.NA_UI_CONFIG, id).label).filter(label => /[-–—]/.test(label)), []);
[
    ['single_door_', window.NA_EXT_SINGLE_DOOR_CONFIG],
    ['double_door_', window.NA_DOUBLE_DOOR_CONFIG],
    ['sliding_door_', window.NA_SLIDING_DOOR_CONFIG],
    ['bifold_door_', window.NA_BIFOLD_DOOR_CONFIG]
].forEach(([prefix, list]) => {
    const control = na_find_control(list, prefix + 'arched_header_enabled');
    na_expect(prefix + ' has its own switch and options', [control.type, control.children.map(child => child.id)],
              ['expandable', [prefix + 'arched_header_height_mm', prefix + 'arched_header_true_arch', prefix + 'arched_header_segments']]);
});

na_suite('Where it sits');
const na_sections = NA_LAYOUTS.windows.sections;
const na_section = key => na_sections.find(section => section.key === key);
const na_sash_item = id => na_section('sashes').items.find(item => item.id === id);
na_expect('Casements > More, drawn as a switch', [na_sash_item('arched_header_enabled').tier, na_sash_item('arched_header_enabled').kind, na_sash_item('arched_header_enabled').products],
          [2, 'switchgroup', ['casement', 'sash']]);
na_expect('its options travel with it', ['arched_header_height_mm', 'arched_header_true_arch', 'arched_header_segments'].map(id => na_sash_item(id).inside),
          ['arched_header_enabled', 'arched_header_enabled', 'arched_header_enabled']);
na_expect('it needs casements to arch', [na_sash_item('arched_header_enabled').showIf({ show_casements: true }), na_sash_item('arched_header_enabled').showIf({ show_casements: false })], [true, false]);
na_expect('the search can switch it on', na_sash_item('arched_header_height_mm').need.fix, [['show_casements', true], ['arched_header_enabled', true]]);
[['single', 'single_door'], ['double', 'double_door'], ['bifold', 'bifold_door'], ['sliding', 'sliding_door']].forEach(([product, prefix]) => {
    const items = na_section('leaves').items;
    const main = items.find(item => item.id === prefix + '_arched_header_enabled');
    na_expect(product + ': Leaves > More, drawn as a switch', [main.tier, main.kind, main.products], [2, 'switchgroup', [product]]);
    na_expect(product + ': hidden on a fully fielded leaf', [main.showIf({ [prefix + '_leaf_composition']: 'FullyGlazed' }), main.showIf({ [prefix + '_leaf_composition']: 'FullyFielded' })], [true, false]);
    na_expect(product + ': the search can give it glass', main.need.fix, [[prefix + '_leaf_composition', 'FullyGlazed']]);
    const height = items.find(item => item.id === prefix + '_arched_header_height_mm');
    na_expect(product + ': options travel with it', [height.inside, height.need.fix], [prefix + '_arched_header_enabled', [[prefix + '_arched_header_enabled', true]]]);
});
const na_double_main = na_section('leaves').items.find(item => item.id === 'double_door_arched_header_enabled');
na_expect('a fielded pair with one glazed leaf override still shows it', na_double_main.showIf({
    double_door_leaf_composition: 'FullyFielded', double_door_leaf_settings_linked: false,
    double_door_left_leaf_override_enabled: true, double_door_left_leaf_composition: 'FullyGlazed'
}), true);
na_expect('Changed and Reset read the switch as a setting', NA_LAYOUTS.windows.defaultOf('arched_header_enabled', 'casement'), false);

na_suite('Section summaries');
const na_sash_summary = cfg => na_section('sashes').summary(Object.assign({ casement_width_mm: 65, casement_inset_mm: 10 }, cfg), 'casement');
na_expect('off: nothing said', na_sash_summary({}).indexOf('arch'), -1);
na_expect('on: the rise', na_sash_summary({ arched_header_enabled: true, arched_header_height_mm: 60 }).indexOf('arched 60') > 0, true);
na_expect('true arch says so', na_sash_summary({ arched_header_enabled: true, arched_header_true_arch: true }).indexOf('true arch') > 0, true);
const na_leaf_summary = cfg => na_section('leaves').summary(Object.assign({ single_door_leaf_composition: 'FullyGlazed' }, cfg), 'single');
na_expect('door leaves say so too', na_leaf_summary({ single_door_arched_header_enabled: true, single_door_arched_header_height_mm: 80 }).indexOf('arched 80') > 0, true);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Window Preview
// -----------------------------------------------------------------------------

na_suite('Window preview: switched off');
const na_flat_svg = Gen.na_generateWindowSvg(na_window());
na_expect('no polygons at all', na_polygons(na_flat_svg).length, 0);
const na_old_window = na_window();
['arched_header_enabled', 'arched_header_height_mm', 'arched_header_true_arch', 'arched_header_segments'].forEach((key) => { delete na_old_window[key]; });
na_expect('a window saved before V2.5.2 draws exactly as it did', Gen.na_generateWindowSvg(na_old_window), na_flat_svg);

na_suite('Window preview: a slight arc');
const na_frame_colour = '#FFFFFF';
const na_arch_svg = Gen.na_generateWindowSvg(na_arched());
const na_heads = na_polygons(na_arch_svg, na_frame_colour);
const na_glass = na_polygons(na_arch_svg, 'rgba(135, 206, 235, 0.3)');
na_expect('one rail and one pane', [na_heads.length, na_glass.length], [1, 1]);
na_expect('rail between the stiles, 65 deep at the crown, 125 at the sides', na_box(na_heads[0]), [115, 785, 1025, 1150]);
na_expect('13 arc points and the top corners', na_heads[0].length, 15);
na_expect('the crown is 65 under the top of the casement', na_r(Math.min(...na_heads[0].filter(([x]) => Math.abs(x - 450) < 0.01).map(([, z]) => z))), 1085);
na_expect('the glass keeps its flat top height at the crown', na_box(na_glass[0]), [115, 785, 115, 1085]);
na_expect('no flat top rail rectangle is left', na_rect_list(na_arch_svg).filter(rect => rect.height === 65 && rect.top === 1150).length, 0);
na_expect('stiles stay full height', na_rect_list(na_arch_svg).filter(rect => rect.width === 65 && rect.height === 1100).length, 2);

na_suite('Window preview: a true arch');
const na_true_svg = Gen.na_generateWindowSvg(na_arched({ arched_header_true_arch: true }));
const na_true_heads = na_polygons(na_true_svg, na_frame_colour);
na_expect('the head spans the full casement', na_box(na_true_heads[0]), [50, 850, 750, 1150]);
na_expect('stiles stop at the springing line', na_rect_list(na_true_svg).filter(rect => rect.width === 65 && rect.height === 700).length, 2);
na_expect('and no full height ones remain', na_rect_list(na_true_svg).filter(rect => rect.width === 65 && rect.height === 1100).length, 0);

na_suite('Window preview: segments');
na_expect('24 segments', na_polygons(Gen.na_generateWindowSvg(na_arched({ arched_header_segments: '24' })), na_frame_colour)[0].length, 27);
na_expect('48 segments', na_polygons(Gen.na_generateWindowSvg(na_arched({ arched_header_segments: '48' })), na_frame_colour)[0].length, 51);

na_suite('Window preview: which casements take it');
const na_count_heads = cfg => na_polygons(Gen.na_generateWindowSvg(cfg), na_frame_colour).length;
na_expect('three lights: three arches', na_count_heads(na_arched({ width_mm: 1800, mullions: 2 })), 3);
na_expect('each light its own, across its own glass', na_polygons(Gen.na_generateWindowSvg(na_arched({ width_mm: 1800, mullions: 2 })), na_frame_colour)
    .map(points => na_r(na_box(points)[1] - na_box(points)[0])), [410, 410, 410]);
na_expect('a transom: only the top casement', na_count_heads(na_arched({ height_mm: 1500, transoms: 1, transom_1_y_mm: 500 })), 1);
na_expect('and it sits above the transom', na_box(na_polygons(Gen.na_generateWindowSvg(na_arched({ height_mm: 1500, transoms: 1, transom_1_y_mm: 500 })), na_frame_colour)[0])[3], 1450);
na_expect('two casements per light: both', na_count_heads(na_arched({ width_mm: 1500, casements_per_opening: 2 })), 2);
na_expect('a casement clicked off has no rail to arch', na_count_heads(na_arched({ removed_casements: ['0:0:0'] })), 0);
na_expect('nor Show Casements off', na_count_heads(na_arched({ show_casements: false })), 0);
const na_own_sizes = na_arched({ casement_overrides: { '0:0:0': { enabled: true, left_stile_mm: 100, right_stile_mm: 100, top_rail_mm: 90, bottom_rail_mm: 65, inset_mm: 10 } } });
na_expect('Per Casement Settings: its own stiles and rail', na_box(na_polygons(Gen.na_generateWindowSvg(na_own_sizes), na_frame_colour)[0]), [150, 750, 1000, 1150]);
const na_individual = na_arched({ casement_sizes_individual: true, casement_top_rail_mm: 120, casement_bottom_rail_mm: 70, casement_left_stile_mm: 40, casement_right_stile_mm: 80 });
const na_individual_head = na_polygons(Gen.na_generateWindowSvg(na_individual), na_frame_colour)[0];
na_expect('Individual Casement Sizes: an uneven pair of stiles centres the arc on the glass', [na_box(na_individual_head)[0], na_box(na_individual_head)[1], na_r(na_individual_head[8][0])], [90, 770, 430]);

na_suite('Window preview: sliding sash');
const na_sash = na_arched({ sliding_sash_window: true, sash_horns_enabled: false, sliding_sash_overlap_mm: 40 });
const na_sash_heads = na_polygons(Gen.na_generateWindowSvg(na_sash), na_frame_colour);
na_expect('the top sash only', na_sash_heads.length, 1);
na_expect('at the head of the window', na_box(na_sash_heads[0])[3], 1150);

na_suite('Window preview: bars and lead go under the rail');
const na_barred = Gen.na_generateWindowSvg(na_arched({ horizontal_glaze_bars: 1, vertical_glaze_bars: 1, leaded_glass_enabled: true, horizontal_leaded_bars: 2, vertical_leaded_bars: 2 }));
const na_head_index = na_barred.indexOf('fill="#FFFFFF" stroke="#000" stroke-width="0.5"/>', na_barred.lastIndexOf('<polygon'));
na_expect('the rail is the last thing drawn in the casement', na_barred.lastIndexOf('<polygon') > na_barred.lastIndexOf('fill="#999999"'), true);
na_expect('its polygon closes before the click targets', na_head_index > 0 && na_barred.indexOf('na-opening-click-target') > na_head_index, true);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Door Previews
// -----------------------------------------------------------------------------

[
    ['Single door preview', 'single_door', 'NA_EXT_SINGLE_DOOR_CONFIG', 'ext_single_door_mode', window.Na__ExtSingleDoor__ElevationGenerator, 1],
    ['Double door preview', 'double_door', 'NA_DOUBLE_DOOR_CONFIG', 'ext_double_door_mode', window.Na__ExtDouble__ElevationGenerator, 2]
].forEach(([title, prefix, array, mode, generator, leaves]) => {
    na_suite(title);
    const render = (overrides) => {
        const root = na_make_node('svg');
        generator.na_render(root, na_hinged(prefix + '_', array, mode, Object.assign({ width_mm: leaves === 2 ? 1800 : 1000, [prefix + '_leaf_composition']: 'FullyGlazed' }, overrides)));
        return root.children;
    };
    const tags = nodes => nodes.filter(node => node.tag === 'polygon' || node.tag === 'polyline').length;
    na_expect('off: no arcs drawn', tags(render({})), 0);
    const on = render({ [prefix + '_arched_header_enabled']: true });
    na_expect('on: glass, rail and arc line per leaf', tags(on), leaves * 3);
    const rail = on.filter(node => node.tag === 'polyline')[0];
    na_expect('the arc has 13 points', rail.attrs.points.split(' ').length, 13);
    const rails = on.map((node, index) => [node, index]).filter(([node]) => node.tag === 'polyline');
    na_expect('the arc is outlined after the bars', rails[0][1] > 0, true);
    na_expect('fully fielded leaves stay flat', tags(render({ [prefix + '_arched_header_enabled']: true, [prefix + '_leaf_composition']: 'FullyFielded' })), 0);
    const hybrid = render({ [prefix + '_arched_header_enabled']: true, [prefix + '_leaf_composition']: 'GlazedOverFielded' });
    na_expect('glazed over fielded: the top glass only', tags(hybrid), leaves * 3);
    const two = render({ [prefix + '_arched_header_enabled']: true, [prefix + '_leaf_composition']: 'GlazedOverGlazed' });
    na_expect('glazed over glazed: the top pane only', tags(two), leaves * 3);
});

[
    ['Sliding door preview', 'sliding_door', cfg => window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg(cfg), { sliding_mode: true, sliding_door_panel_count: 2 }, 2],
    ['Bifold door preview', 'bifold_door', cfg => window.Na__ExtFold__ElevationGenerator.na_generate_bifold_svg(cfg), { multifold_mode: true, bifold_door_panel_count: 4, bifold_door_leaf_composition: 'FullyGlazed' }, 4]
].forEach(([title, prefix, generate, mode, panels]) => {
    na_suite(title);
    const set = Object.assign({ width_mm: 3000, height_mm: 2100, frame_thickness_mm: 50, has_cill: true, cill_height_mm: 50, cill_depth_mm: 50,
                                show_dimensions: false, horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25 }, mode);
    const off = generate(set);
    na_expect('off: no polygons', na_polygons(off).length, 0);
    const on = generate(Object.assign({}, set, { [prefix + '_arched_header_enabled']: true, [prefix + '_arched_header_height_mm']: 60 }));
    na_expect('on: a rail and a pane per leaf', na_polygons(on).length, panels * 2);
    const flatRails = na_rect_list(off).filter(rect => na_r(rect.height) === 95);   // <-- The flat head rails it replaces, 95 stiles either side
    const glassWidth = flatRails[0].width;
    const leafWidth = glassWidth + 190;
    const railTop = flatRails[0].top;
    na_expect('(one flat head rail per leaf, to measure against)', flatRails.length, panels);
    const segmental = na_polygons(on).filter(points => na_r(na_box(points)[3]) === na_r(railTop));
    na_expect('a slight arc: a rail between the stiles on each leaf', segmental.map(points => na_r(na_box(points)[1] - na_box(points)[0])), new Array(panels).fill(na_r(glassWidth)));
    na_expect('its top stays where the flat rail was, 95 over the crown', segmental.map(points => na_r(railTop - Math.min(...points.filter(([x]) => Math.abs(x - (na_box(points)[0] + na_box(points)[1]) / 2) < 0.01).map(([, z]) => z)))), new Array(panels).fill(95));
    na_expect('no flat rail is left under it', na_rect_list(on).filter(rect => na_r(rect.height) === 95).length, 0);
    const stileHeights = svg => na_rect_list(svg).filter(rect => na_r(rect.width) === 95).map(rect => na_r(rect.height));
    na_expect('a slight arc: the stiles run the full leaf', stileHeights(on), new Array(panels * 2).fill(2000));
    const trueSvg = generate(Object.assign({}, set, { [prefix + '_arched_header_enabled']: true, [prefix + '_arched_header_true_arch']: true }));
    const heads = na_polygons(trueSvg).filter(points => na_r(na_box(points)[3]) === na_r(railTop));
    na_expect('a true arch: the head spans the whole leaf', heads.map(points => na_r(na_box(points)[1] - na_box(points)[0])), new Array(panels).fill(na_r(leafWidth)));
    na_expect('and it springs half the glass under the crown', heads.map(points => na_r(na_box(points)[2])), new Array(panels).fill(na_r(railTop - 95 - glassWidth / 2)));
    na_expect('a true arch: the stiles stop at the springing line', stileHeights(trueSvg), new Array(panels * 2).fill(na_r(2000 - 95 - glassWidth / 2)));
    const fielded = generate(Object.assign({}, set, { [prefix + '_arched_header_enabled']: true, [prefix + '_leaf_composition']: 'FullyFielded', [prefix + '_glazed']: false }));
    na_expect('fully fielded stays flat', na_polygons(fielded).length, 0);
});

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DXF
// -----------------------------------------------------------------------------

na_suite('Window DXF (browser fallback)');
const Dxf = window.Na__Export__Dxf;
const na_panel = { openingIndex: 0, cellIndex: 0, panelIndex: 0, sashIndex: 0 };
const na_casement_dxf = (hBars, vBars, settings) => Dxf.na_generateCasementDxf(50, 50, 800, 1100, 65, 65, 65, 65, hBars, vBars, 25, na_panel, new Set(), {}, settings);
const na_flat_dxf = na_dxf_lines(na_casement_dxf(0, 0, null), null);
na_expect('flat: four members and the glass, four lines each', na_flat_dxf.length, 20);
const na_arch_dxf = na_dxf_lines(na_casement_dxf(0, 0, { riseMm: 60, trueArch: false, segments: 12 }), null);
na_expect('arched: 3 members, then rail and glass outlines of 14 and 14 sides plus one', na_arch_dxf.length, 12 + 15 + 15);
const na_bar_dxf = na_dxf_lines(na_casement_dxf(0, 1, { riseMm: 60, trueArch: false, segments: 12 }), null);
const na_v_bar = na_bar_dxf.slice(na_arch_dxf.length);
na_expect('a vertical bar stops at the arc, not the flat glass top', na_v_bar.length === 4 && Math.max(...na_v_bar.flatMap(line => [line[1], line[3]])) <= 1085 && Math.max(...na_v_bar.flatMap(line => [line[1], line[3]])) > 1080, true);
const na_three_bars = na_dxf_lines(na_casement_dxf(0, 3, { riseMm: 200, trueArch: false, segments: 12 }), null).slice(12 + 15 + 15);
const na_bar_tops = [0, 4, 8].map(start => Math.max(...na_three_bars.slice(start, start + 4).flatMap(line => [line[1], line[3]])));
na_expect('three bars: each rectangle stops at the arc over its side nearest the crown', [na_three_bars.length, na_r(na_bar_tops[0]), na_r(na_bar_tops[2]), na_bar_tops[1]], [12, 1052, 1052, 1085]);   // <-- r 380.56, centre 704.44, the first bar's inner edge 155 from the middle
const na_true_dxf = na_dxf_lines(na_casement_dxf(0, 0, { riseMm: 60, trueArch: true, segments: 12 }), null);
na_expect('true arch: stiles stop at the springing line', na_true_dxf.slice(0, 4).every(line => Math.max(line[1], line[3]) <= 750), true);
const na_extra_lines = (overrides) => {                              // <-- Lines an arch adds to the whole export: one casement's rail and glass grow 22 (fallback has one layer)
    const count = cfg => na_dxf_lines(Dxf.na_exportDxf(cfg), null).length;
    return count(na_arched(overrides)) - count(na_window(overrides));
};
na_expect('the whole window export carries the arch', na_extra_lines({}), 22);
na_expect('every light in it', na_extra_lines({ width_mm: 1800, mullions: 2 }), 66);
na_expect('the top casement only, over a transom', na_extra_lines({ height_mm: 1500, transoms: 1, transom_1_y_mm: 500 }), 22);
na_expect('the top sash only', na_extra_lines({ sliding_sash_window: true, sash_horns_enabled: false }), 22);

na_suite('Hinged door DXF');
const na_door_dxf = overrides => window.Na__ExtSingleDoor__DxfExporter.na_export_dxf(na_hinged('single_door_', 'NA_EXT_SINGLE_DOOR_CONFIG', 'ext_single_door_mode', Object.assign({ single_door_leaf_composition: 'FullyGlazed' }, overrides)));
const na_top = (lines) => Math.max(...lines.flatMap(line => [line[1], line[3]]));
const na_glass_flat = na_dxf_lines(na_door_dxf({}), 'NA_GLASS');
const na_glass_on = na_dxf_lines(na_door_dxf({ single_door_arched_header_enabled: true }), 'NA_GLASS');
na_expect('flat glass: four lines', na_glass_flat.length, 4);
na_expect('arched glass: the outline, 12 facets more', na_glass_on.length, 15);
na_expect('its crown stays at the flat top', na_r(na_top(na_glass_on)), na_r(na_top(na_glass_flat)));
const na_door_bars = na_dxf_lines(na_door_dxf({ single_door_arched_header_enabled: true, single_door_arched_header_height_mm: 200, vertical_glaze_bars: 3 }), 'NA_GLAZEBAR');
na_expect('three bars: the outer two stop short of the middle one', [na_door_bars.length, na_top(na_door_bars.slice(0, 1)) < na_top(na_door_bars.slice(1, 2))], [3, true]);
na_expect('fully fielded: no arch', na_dxf_lines(na_door_dxf({ single_door_arched_header_enabled: true, single_door_leaf_composition: 'FullyFielded' }), 'NA_GLASS').length, 0);
const na_stile_tops = (overrides) => {
    const members = na_dxf_lines(na_door_dxf(overrides), 'NA_RAIL_STILE');
    return Math.max(...members.filter(line => line[0] === 145 && line[2] === 145).flatMap(line => [line[1], line[3]]));
};
na_expect('a slight arc: the stiles run the full leaf', na_stile_tops({ single_door_arched_header_enabled: true }), 2100);
na_expect('a true arch: they stop at the springing line', na_stile_tops({ single_door_arched_header_enabled: true, single_door_arched_header_true_arch: true }), 1650);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Slider, Saved Elements and Door Type Switch
// -----------------------------------------------------------------------------

na_suite('The height slider follows the element');
Ui.na_setConfig(na_window({ width_mm: 900, arched_header_enabled: true, arched_header_height_mm: 60 }));
na_expect('tops out at a true arch over the widest glass', [na_element('arched_header_height_mm-slider').max, na_element('arched_header_height_mm-input').max], ['335', '335']);
Ui.na_setConfig({ width_mm: 1500 });
na_expect('wider window, higher top', na_element('arched_header_height_mm-slider').max, '635');
na_expect('the set height stays', Ui.na_getConfig().arched_header_height_mm, 60);
Ui.na_setConfig({ arched_header_true_arch: true });
na_expect('True Arch hides the height', na_element('arched_header_height_mm').style.display, 'none');
Ui.na_setConfig({ arched_header_true_arch: false });
na_expect('and brings it back', na_element('arched_header_height_mm').style.display, '');

na_suite('The height slider follows each door type');
const na_door_slider = (product, prefix, overrides) => {
    Ui.na_setProduct('ExteriorDoors', product);
    Ui.na_setConfig(Object.assign({ width_mm: 2000, height_mm: 2100, frame_thickness_mm: 50, advanced_frame_controls: false, [prefix + 'arched_header_enabled']: true, [prefix + 'arched_header_height_mm']: 60, [prefix + 'leaf_composition']: 'FullyGlazed' }, overrides));
    return na_element(prefix + 'arched_header_height_mm-slider').max;
};
na_expect('single: 1900 leaf less 95 stiles, halved, rounded up to a stop', na_door_slider('Single', 'single_door_', {}), '855');
na_expect('double: 950 leaf', na_door_slider('Double', 'double_door_', {}), '380');
na_expect('sliding: 950 leaf', na_door_slider('Sliding', 'sliding_door_', { sliding_door_panel_count: 2 }), '380');
na_expect('bifold: 475 leaf', na_door_slider('MultiFold', 'bifold_door_', { bifold_door_panel_count: 4 }), '145');
Ui.na_setProduct('Window', 'Casement');

na_suite('Older elements and partial updates');
Ui.na_setConfig({ arched_header_enabled: true, width_mm: 900 });
na_expect('a partial update leaves the switch', Ui.na_getConfig().arched_header_enabled, true);
Ui.na_setConfig({ width_mm: 1500 }, { fullConfig: true });
na_expect('an element saved before V2.5.2 does not take on the last one\'s arch', Ui.na_getConfig().arched_header_enabled, false);
Ui.na_setConfig({ width_mm: 1500, single_door_arched_header_enabled: true }, { fullConfig: true });
na_expect('one saved with an arch keeps it', Ui.na_getConfig().single_door_arched_header_enabled, true);
Ui.na_setConfig({ width_mm: 900 }, { fullConfig: true });
na_expect('nor does a door type\'s arch ride along', Ui.na_getConfig().single_door_arched_header_enabled, false);

na_suite('Door type switch keeps it');
Ui.na_setProduct('ExteriorDoors', 'Single');
Ui.na_applyControlChange('single_door_arched_header_enabled', true);
Ui.na_applyControlChange('single_door_arched_header_height_mm', 110);
Ui.na_applyControlChange('single_door_arched_header_segments', '24');
Ui.na_setProduct('ExteriorDoors', 'Sliding');
na_expect('carried to the sliding set', [Ui.na_getConfig().sliding_door_arched_header_enabled, Ui.na_getConfig().sliding_door_arched_header_height_mm, Ui.na_getConfig().sliding_door_arched_header_segments], [true, 110, '24']);
Ui.na_setProduct('ExteriorDoors', 'Double');
na_expect('and on to the pair', [Ui.na_getConfig().double_door_arched_header_enabled, Ui.na_getConfig().double_door_arched_header_height_mm], [true, 110]);
Ui.na_setProduct('Window', 'Casement');

na_suite('Ruby side agrees');
const na_read = relative => fs.readFileSync(path.join(NA_MODULES, relative), 'utf8');
const na_defaults = na_read('20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Defaults__.rb');
na_expect('default config: off', /"arched_header_enabled"\s*:\s*false/.test(na_defaults), true);
na_expect('default config: same height as the slider', new RegExp('"arched_header_height_mm"\\s*:\\s*' + na_height_control.default + '\\b').test(na_defaults), true);
na_expect('default config: same segments as the select', new RegExp('"arched_header_segments"\\s*:\\s*"' + na_segment_control.default + '"').test(na_defaults), true);
[
    ['31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__Init__.rb', 'single_door_'],
    ['34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__Init__.rb', 'double_door_'],
    ['32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__Init__.rb', 'sliding_door_'],
    ['33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__Init__.rb', 'bifold_door_']
].forEach(([relative, prefix]) => {
    const source = na_read(relative);
    na_expect(prefix + ' default config holds all four', ['enabled', 'height_mm', 'true_arch', 'segments'].filter(key => source.indexOf(prefix + 'arched_header_' + key) === -1), []);
});
[
    ['31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__PanelLayoutResolver__.rb', 'single_door_'],
    ['34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__PanelLayoutResolver__.rb', 'double_door_'],
    ['32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__PanelLayoutResolver__.rb', 'sliding_door_'],
    ['33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__PanelLayoutResolver__.rb', 'bifold_door_']
].forEach(([relative, prefix]) => {
    na_expect(path.basename(relative) + ' reads its own settings', na_read(relative).indexOf("na_settings(config, '" + prefix + "')") >= 0, true);
});
const na_ruby_builder = na_read('20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__ArchedHeaderBuilder__.rb');
const na_ruby_number = name => Number(new RegExp(name + '\\s*=\\s*([0-9.]+)').exec(na_ruby_builder)[1]);
const na_js_math = na_read('20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__ArchMath__.js');
const na_js_number = name => Number(new RegExp('const ' + name + '\\s*=\\s*([0-9.]+)').exec(na_js_math)[1]);
na_expect('the two maths files hold the same limits', [
    na_ruby_number('NA_ARCH_MIN_RISE_MM'), na_ruby_number('NA_ARCH_DEFAULT_RISE_MM'), na_ruby_number('NA_ARCH_MIN_SIDE_MM'),
    na_ruby_number('NA_ARCH_MIN_LIMIT_MM'), na_ruby_number('NA_ARCH_TRUE_TOLERANCE_MM')
], [
    na_js_number('NA_MIN_RISE_MM'), na_js_number('NA_DEFAULT_RISE_MM'), na_js_number('NA_MIN_SIDE_MM'),
    na_js_number('NA_MIN_LIMIT_MM'), na_js_number('NA_TRUE_TOLERANCE_MM')
]);

na_suite('The dialog loads it');
const na_html = fs.readFileSync(path.join(NA_ROOT, 'Na__AssemblyStudio__UiLayout__.html'), 'utf8');
na_expect('the maths loads before the previews need it', na_html.indexOf('Viewport__ArchMath__.js') > 0 && na_html.indexOf('Viewport__ArchMath__.js') < na_html.indexOf('Viewport__SvgGenerator__.js'), true);

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);
