/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - PREVIEW DIMENSIONS, CAD ZOOM AND LEAD MARGINS SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__PreviewDimensions__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for V2.2.0 - the preview's mullion and
                transom set out chains, typing a size over any preview
                dimension, the CAD style zoom and pan, and Lead Line Margins -
                and V2.2.1, single lead lines clicked off in the preview.
   CREATED    : 01-Nov-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__PreviewDimensions__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHAT IT COVERS
   - Na__GlazebarMath.na_computeLeadPositions: even layout, margins, one
     line, a margin too big for the pane, a pane too small for any margin.
   - The window preview's lead lines with Lead Line Margins on and off.
   - Na__Viewport__SvgGenerator: the chains' stations, which station a
     typed segment moves, what a typed size becomes in the config, and the
     editable markup (the door previews' overall sizes too).
   - Na_DynamicUI.na_applyDimensionEdit, the real panel logic: sums,
     relative entries, an unchanged size, an unreadable one, a mullion and
     a transom typed over, and the V2.2.0 hydration of an older window.
   - Na__Viewport__Controls + Na__Viewport__Instance against a fake SVG
     whose screen matrix follows its viewBox exactly as a browser's does
     (preserveAspectRatio meet): the wheel keeps the point under the cursor
     still, a drag keeps the drawing under the cursor, a jitter is still a
     click, double clicks fit, and a zoom survives edits only where asked.
   - V2.2.1: lead line keys, one click strip per line (kept when the line is
     off), a line clicked off and on through Na_DynamicUI, keys pruned when
     the count drops, Reset Elements, an older window selected, and the
     click delegation (a pan's closing click ignored).
   - V2.2.2: the X and Y lead margins switched on their own, in the
     resolver, the preview, and how an older window loads.

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

// HELPER FUNCTION | Assert Two Numbers Agree to a Tolerance
// ------------------------------------------------------------
function na_near(label, actual, expected, tolerance) {
    const ok = Math.abs(Number(actual) - Number(expected)) <= (tolerance || 1e-6);
    na_expect(label, ok ? 'within tolerance' : actual, ok ? 'within tolerance' : expected);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Print a Suite Heading
// ------------------------------------------------------------
function na_suite(title) {
    console.log('\n' + title);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Round to 3 dp for Comparisons
// ------------------------------------------------------------
function na_r3(value) {
    return Math.round(value * 1000) / 1000;
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Fake Canvas (Wrapper + SVG With a Real Screen Matrix)
// -----------------------------------------------------------------------------

// HELPER FUNCTION | Event Target That Records Listeners
// ------------------------------------------------------------
function na_event_target(target) {
    const listeners = {};
    target.addEventListener = (type, handler) => { (listeners[type] = listeners[type] || []).push(handler); };
    target.removeEventListener = (type, handler) => {
        listeners[type] = (listeners[type] || []).filter(existing => existing !== handler);
    };
    target.na_dispatch = (type, event) => {
        (listeners[type] || []).slice().forEach(handler => handler(event));
    };
    return target;
}
// ---------------------------------------------------------------

// FUNCTION | Build an SVG Stand-In Whose Screen Matrix Follows Its viewBox
// ------------------------------------------------------------
// The element sits at (left, top) with the given size, and maps its
// viewBox with preserveAspectRatio xMidYMid meet, as the preview's SVG does.
function na_fake_svg(left, top, width, height) {
    const attributes = {};
    const svg = na_event_target({
        setAttribute: (name, value) => { attributes[name] = String(value); },
        getAttribute: (name) => (name in attributes ? attributes[name] : null),
        contains: () => true,
        closest: () => null,
        getScreenCTM: () => {
            const box = (attributes.viewBox || '0 0 ' + width + ' ' + height).split(' ').map(Number);
            const scale = Math.min(width / box[2], height / box[3]);
            const e = left + (width - box[2] * scale) / 2 - box[0] * scale;
            const f = top + (height - box[3] * scale) / 2 - box[1] * scale;
            return {
                a: scale, b: 0, c: 0, d: scale, e: e, f: f,
                inverse: () => ({ a: 1 / scale, b: 0, c: 0, d: 1 / scale, e: -e / scale, f: -f / scale })
            };
        }
    });
    return svg;
}
// ---------------------------------------------------------------

// FUNCTION | Build a Canvas Wrapper Stand-In
// ------------------------------------------------------------
function na_fake_wrapper() {
    const classes = new Set();
    return na_event_target({
        classList: { add: (name) => classes.add(name), contains: (name) => classes.has(name) },
        style: {},
        na_classes: classes
    });
}
// ---------------------------------------------------------------

// HELPER FUNCTION | A Target Whose closest() Finds (or Misses) a Clickable Part
// ------------------------------------------------------------
function na_target(isClickable) {
    return { closest: () => (isClickable ? {} : null) };
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Stub and Shipped Modules
// -----------------------------------------------------------------------------

// Element lookups miss (the UI logic guards each one) except the fake
// canvases registered by the Instance suite.
const na_fake_elements = {};
let na_onControlChange = null;

global.window = global;
na_event_target(global);                                             // <-- Window level mousemove / mouseup for drags
global.document = {
    getElementById   : (id) => {
        if (na_fake_elements[id]) return na_fake_elements[id];
        return String(id).indexOf('na-controls-') === 0 ? { innerHTML: '', insertAdjacentHTML: () => {} } : null;
    },
    querySelector    : () => null,
    querySelectorAll : () => [],
    addEventListener : () => {},
    createElementNS  : () => ({ setAttribute: () => {}, appendChild: () => {} }),
    createElement    : () => ({ appendChild: () => {} })
};
window.Na__Ui__Controls = { na_createControl: () => '' };
window.Na__Ui__Events   = { na_attachEventListeners: (config, callback) => { na_onControlChange = callback; } };
const na_console_error  = console.error;
console.error = (message, ...rest) => {                              // <-- No window viewport is built here; keep every other error
    if (String(message).indexOf('[NA_VIEWPORT]') === 0) return;
    na_console_error(message, ...rest);
};

const NA_SOURCES = [
    '03__AppUtils/Na__AssemblyStudio__AppUtils__ArithmeticEvaluator__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__Config__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__MullionMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__CasementMath__.js',
    '05__Viewport__2dPreviewEngine/Na__AssemblyStudio__Viewport__Controls__.js',
    '05__Viewport__2dPreviewEngine/Na__AssemblyStudio__Viewport__Instance__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__Viewport__ElevationGenerator__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__MainUiLogic__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Bridge__.js'
];

// Each shipped file declares top-level `const`s and `let`s, which would
// collide across a shared eval scope, so every source runs in its own.
const na_console_log = console.log;
console.log = () => {};                                              // <-- Silence the dialog's own logging
NA_SOURCES.forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + fs.readFileSync(path.join(NA_MODULES, relativePath), 'utf8') + '\n})()');
});

const Ui = window.Na_DynamicUI;
const Math2d = window.Na__GlazebarMath;
const Generator = window.Na__Viewport__SvgGenerator;
const Controls = window.Na__Viewport__Controls;
Ui.na_init();
console.log = (message, ...rest) => {                                // <-- Keep the suite's output, drop the dialog's own [NA_*] logging
    if (String(message).indexOf('[NA_') === 0) return;
    na_console_log(message, ...rest);
};

// The window the suites set out: 1800 x 1200, 50 frame, two 40 mullions,
// so three 540 lights at x 50, 630 and 1210.
const NA_WINDOW = {
    width_mm: 1800, height_mm: 1200, frame_thickness_mm: 50, advanced_frame_controls: false,
    mullions: 2, mullion_width_mm: 40, mullion_offsets_enabled: false,
    mullion_offset_1_mm: 0, mullion_offset_2_mm: 0,
    transoms: 0, transom_width_mm: 40, transom_1_y_mm: 700,
    casement_width_mm: 65, casement_sizes_individual: true,
    casement_top_rail_mm: 60, casement_bottom_rail_mm: 70,
    casement_left_stile_mm: 40, casement_right_stile_mm: 40,
    show_casements: true, casements_per_opening: 1, sliding_sash_window: false,
    horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25,
    leaded_glass_enabled: false, show_dimensions: true, has_cill: true, cill_height_mm: 50,
    removed_casements: [], removed_transom_segments: [], removed_glazebars: [], leaded_disabled_cells: []
};

// HELPER FUNCTION | A Window Config With Some Keys Changed
// ------------------------------------------------------------
function na_window(overrides) {
    return Object.assign({}, NA_WINDOW, overrides || {});
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Segment Lengths of a Chain
// ------------------------------------------------------------
function na_segments(stations) {
    if (!Array.isArray(stations)) return null;
    return stations.slice(1).map((station, index) => na_r3(station - stations[index]));
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Lead Centrelines Drawn in a Window Preview (Centre Lines Mode)
// ------------------------------------------------------------
// @returns {Object} { h: [y up...], v: [x...] } sorted, rounded
function na_preview_leads(config) {
    const cfg = Object.assign({}, config, { leaded_centre_lines_only: true, show_dimensions: false });
    const stroke = Generator.na_leadedColourHex(Generator.na_resolveLeadedColourId(cfg));
    const svg = Generator.na_generateWindowSvg(cfg);
    const pattern = /<line x1="([-\d.e]+)" y1="([-\d.e]+)" x2="([-\d.e]+)" y2="([-\d.e]+)" stroke="([^"]+)" stroke-width="1" \/>/g;
    const leads = { h: [], v: [] };
    let match;
    while ((match = pattern.exec(svg)) !== null) {
        if (match[5] !== stroke) continue;
        if (match[2] === match[4]) leads.h.push(na_r3(-Number(match[2])));
        else if (match[1] === match[3]) leads.v.push(na_r3(Number(match[1])));
    }
    leads.h.sort((a, b) => a - b);
    leads.v.sort((a, b) => a - b);
    return leads;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Read the Editable Dimension Groups Out of SVG Markup
// ------------------------------------------------------------
function na_editable_dims(svg) {
    const pattern = /<g class="na-dim-edit" data-dim-kind="([^"]+)" data-dim-index="(\d+)" data-dim-value="([^"]+)"/g;
    const dims = [];
    let match;
    while ((match = pattern.exec(svg)) !== null) {
        dims.push([match[1], Number(match[2]), na_r3(Number(match[3]))]);
    }
    return dims;
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suites
// -----------------------------------------------------------------------------

na_suite('Lead positions (Na__GlazebarMath.na_computeLeadPositions)');
na_expect('no margin: count + 1 equal panes', Math2d.na_computeLeadPositions(0, 100, 3, null, 6), [25, 50, 75]);
na_expect('margin, two lines sit on the margins', Math2d.na_computeLeadPositions(0, 100, 2, 10, 6), [10, 90]);
na_expect('margin, five lines divide between them', Math2d.na_computeLeadPositions(0, 100, 5, 10, 6).map(na_r3), [10, 30, 50, 70, 90]);
na_expect('margin, offset start', Math2d.na_computeLeadPositions(200, 100, 2, 10, 6), [210, 290]);
na_expect('one line stays in the middle', Math2d.na_computeLeadPositions(0, 100, 1, 10, 6), [50]);
na_expect('a margin too big closes the lines to a lead width apart',
    Math2d.na_computeLeadPositions(0, 100, 5, 60, 6).map(na_r3), [38, 44, 50, 56, 62]);
na_expect('a pane too small for any margin keeps the even layout',
    Math2d.na_computeLeadPositions(0, 20, 5, 10, 6).map(na_r3), Math2d.na_computeLeadPositions(0, 20, 5, null, 6).map(na_r3));
na_expect('margin zero puts the outer lines on the edges', Math2d.na_computeLeadPositions(0, 100, 2, 0, 6), [0, 100]);
na_expect('no lines, no positions', Math2d.na_computeLeadPositions(0, 100, 0, 10, 6), []);
na_expect('cells: each laid out inside its own margins',
    Math2d.na_computeLeadLinePositions([{ start: 0, size: 100 }, { start: 125, size: 100 }], 2, 10, 6), [10, 90, 135, 215]);
na_expect('cells without a margin divide evenly (as V2.1.1)',
    Math2d.na_computeLeadLinePositions([{ start: 0, size: 90 }], 2), [30, 60]);

na_suite('Lead Line Margins switch (na_resolveLeadMargins)');
na_expect('off: null', Generator.na_resolveLeadMargins({ leaded_margin_x_mm: 30 }), null);
na_expect('on: both values', Generator.na_resolveLeadMargins({ leaded_margins_enabled: true, leaded_margin_x_mm: 30, leaded_margin_y_mm: 40 }), { x: 30, y: 40 });
na_expect('on, no values yet: the 50 default', Generator.na_resolveLeadMargins({ leaded_margins_enabled: true }), { x: 50, y: 50 });
na_expect('never below zero', Generator.na_resolveLeadMargins({ leaded_margins_enabled: true, leaded_margin_x_mm: -5, leaded_margin_y_mm: 0 }), { x: 0, y: 0 });

na_suite('Lead in the window preview');
// Casement glass: x 90..550 / 670..1130 / 1250..1710, y 120..1090 (970 tall).
const na_leaded = { leaded_glass_enabled: true, horizontal_leaded_bars: 6, vertical_leaded_bars: 3, leaded_width_mm: 6 };
const na_even = na_preview_leads(na_window(na_leaded));
na_expect('margins off: rows divide the 970 glass evenly',
    na_even.h.filter((y, i, all) => all.indexOf(y) === i), [1, 2, 3, 4, 5, 6].map(k => na_r3(120 + 970 / 7 * k)));
const na_margined = na_preview_leads(na_window(Object.assign({ leaded_margins_enabled: true, leaded_margin_x_mm: 30, leaded_margin_y_mm: 40 }, na_leaded)));
na_expect('margins on: rows 40 in from top and bottom, evenly between',
    na_margined.h.filter((y, i, all) => all.indexOf(y) === i), [160, 338, 516, 694, 872, 1050]);
na_expect('margins on: verticals 30 in from each side of each light',
    na_margined.v, [120, 320, 520, 700, 900, 1100, 1280, 1480, 1680]);
na_expect('switched off with values set: as if never set',
    na_preview_leads(na_window(Object.assign({ leaded_margins_enabled: false, leaded_margin_x_mm: 30, leaded_margin_y_mm: 40 }, na_leaded))), na_even);

na_suite('Set out chains (na_computeDimensionChains)');
const na_chains = Generator.na_computeDimensionChains(na_window());
na_expect('mullion stations: frame edge, mullion centrelines, frame edge', na_chains.mullions, [0, 610, 1190, 1800]);
na_expect('mullion segments', na_segments(na_chains.mullions), [610, 580, 610]);
na_expect('no transoms, no transom chain', na_chains.transoms, null);
na_expect('no mullions, no mullion chain', Generator.na_computeDimensionChains(na_window({ mullions: 0 })).mullions, null);
na_expect('mullion offsets move their station',
    Generator.na_computeDimensionChains(na_window({ mullion_offsets_enabled: true, mullion_offset_1_mm: -100 })).mullions, [0, 510, 1190, 1800]);
na_expect('one transom: stations bottom, centreline (50 + 700 + 20), top',
    Generator.na_computeDimensionChains(na_window({ transoms: 1 })).transoms, [0, 770, 1200]);
na_expect('two transoms in order',
    Generator.na_computeDimensionChains(na_window({ transoms: 2, transom_1_y_mm: 300, transom_2_y_mm: 800 })).transoms, [0, 370, 870, 1200]);

na_suite('Which station a typed segment moves (na_solveChainSegmentEdit)');
const na_stations = [0, 610, 1190, 1800];
na_expect('first segment moves its far end', Generator.na_solveChainSegmentEdit(na_stations, 0, 500), { station: 1, position: 500 });
na_expect('middle segment moves its far end', Generator.na_solveChainSegmentEdit(na_stations, 1, 500), { station: 2, position: 1110 });
na_expect('last segment moves its near end (the frame stays)', Generator.na_solveChainSegmentEdit(na_stations, 2, 500), { station: 2, position: 1300 });
na_expect('one mullion: last segment', Generator.na_solveChainSegmentEdit([0, 900, 1800], 1, 600), { station: 1, position: 1200 });
na_expect('a segment past the end', Generator.na_solveChainSegmentEdit(na_stations, 3, 500), null);
na_expect('no chain', Generator.na_solveChainSegmentEdit(null, 0, 500), null);

na_suite('What a typed size becomes (na_resolveDimensionEdit)');
na_expect('width', Generator.na_resolveDimensionEdit(na_window(), 'width', 0, 2000), { changes: { width_mm: 2000 } });
na_expect('height', Generator.na_resolveDimensionEdit(na_window(), 'height', 0, 1500), { changes: { height_mm: 1500 } });
const na_left = Generator.na_resolveDimensionEdit(na_window(), 'mullion', 0, 500);
na_expect('first light typed to 500: mullion 1 moves 110 left, mullion 2 stays',
    na_left, { changes: { mullion_offsets_enabled: true, mullion_offset_1_mm: -110, mullion_offset_2_mm: 0 } });
na_expect('and the chain then reads 500, 690, 610',
    na_segments(Generator.na_computeDimensionChains(na_window(na_left.changes)).mullions), [500, 690, 610]);
const na_right = Generator.na_resolveDimensionEdit(na_window(), 'mullion', 2, 500);
na_expect('last light typed to 500: mullion 2 moves 110 right',
    na_segments(Generator.na_computeDimensionChains(na_window(na_right.changes)).mullions), [610, 690, 500]);
const na_mid = Generator.na_resolveDimensionEdit(na_window(), 'mullion', 1, 500);
na_expect('middle typed to 500: the light after it takes the difference',
    na_segments(Generator.na_computeDimensionChains(na_window(na_mid.changes)).mullions), [610, 500, 690]);
const na_kept = Generator.na_resolveDimensionEdit(
    na_window({ mullion_offsets_enabled: true, mullion_offset_1_mm: 12.345, mullion_offset_2_mm: -7.5 }), 'mullion', 0, 600);
na_expect('offsets already on: the mullion not moved keeps its stored offset exactly', na_kept.changes.mullion_offset_2_mm, -7.5);
na_expect('offsets off with stale hidden values: unmoved mullion written where it is drawn',
    Generator.na_resolveDimensionEdit(na_window({ mullion_offset_2_mm: 300 }), 'mullion', 0, 500).changes.mullion_offset_2_mm, 0);
const na_top = Generator.na_resolveDimensionEdit(na_window({ transoms: 1 }), 'transom', 1, 300);
na_expect('top light typed to 300: the transom moves, stored as its bottom above the frame', na_top, { changes: { transom_1_y_mm: 830 } });
na_expect('and the chain then reads 900, 300',
    na_segments(Generator.na_computeDimensionChains(na_window(Object.assign({ transoms: 1 }, na_top.changes))).transoms), [900, 300]);
na_expect('bottom light typed to 600', Generator.na_resolveDimensionEdit(na_window({ transoms: 1 }), 'transom', 0, 600), { changes: { transom_1_y_mm: 530 } });
na_expect('a mullion chain that is not drawn', !!Generator.na_resolveDimensionEdit(na_window({ mullions: 0 }), 'mullion', 0, 500).error, true);
na_expect('not a number', !!Generator.na_resolveDimensionEdit(na_window(), 'width', 0, 'abc').error, true);

na_suite('Editable markup');
const na_svg = Generator.na_generateWindowSvg(na_window({ transoms: 1 }));
na_expect('every value marked up: overall width, height, three mullion and two transom segments', na_editable_dims(na_svg), [
    ['width', 0, 1800], ['height', 0, 1200],
    ['mullion', 0, 610], ['mullion', 1, 580], ['mullion', 2, 610],
    ['transom', 0, 770], ['transom', 1, 430]
]);
na_expect('each carries a tooltip', (na_svg.match(/click to type a new size<\/title>/g) || []).length, 7);
na_expect('segment values drawn without a unit', /<text[^>]*>580<\/text>/.test(na_svg), true);
na_expect('overall width drawn as before', /<text[^>]*>1800mm<\/text>/.test(na_svg), true);
na_expect('Dimensions off: none drawn', na_editable_dims(Generator.na_generateWindowSvg(na_window({ show_dimensions: false }))), []);
na_expect('old two argument call (any other caller): plain, not editable', na_editable_dims(Generator.na_svgDimensions(1800, 1200)), []);
const na_sliding = window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg(na_window({ sliding_mode: true, width_mm: 3000, height_mm: 2100 }));
na_expect('sliding door preview: overall sizes editable', na_editable_dims(na_sliding), [['width', 0, 3000], ['height', 0, 2100]]);

na_suite('Typing over a dimension (Na_DynamicUI.na_applyDimensionEdit)');
Ui.na_setConfig(na_window());
na_expect('width typed', Ui.na_applyDimensionEdit('width', 0, '2000'), { ok: true, changed: true });
na_expect('width now 2000', Ui.na_getConfig().width_mm, 2000);
Ui.na_applyDimensionEdit('width', 0, '+100');
na_expect('relative entry adds to the size shown', Ui.na_getConfig().width_mm, 2100);
Ui.na_applyDimensionEdit('width', 0, '3600/2');
na_expect('a sum is worked out', Ui.na_getConfig().width_mm, 1800);
na_expect('the same size: nothing rebuilt', Ui.na_applyDimensionEdit('width', 0, '1800'), { ok: true, changed: false });
const na_bad = Ui.na_applyDimensionEdit('width', 0, 'abc');
na_expect('an unreadable entry is refused with a reason', [na_bad.ok, typeof na_bad.error], [false, 'string']);
na_expect('and changes nothing', Ui.na_getConfig().width_mm, 1800);
na_expect('first light typed over', Ui.na_applyDimensionEdit('mullion', 0, '500').ok, true);
const na_after = Ui.na_getConfig();
na_expect('Individual Mullion Offsets switched on, offsets written',
    [na_after.mullion_offsets_enabled, na_after.mullion_offset_1_mm, na_after.mullion_offset_2_mm], [true, -110, 0]);
na_expect('the chain reads what was typed', na_segments(Generator.na_computeDimensionChains(na_after).mullions), [500, 690, 610]);
Ui.na_applyDimensionEdit('mullion', 2, '-10');
na_expect('relative entry on a segment: the last light loses 10',
    na_segments(Generator.na_computeDimensionChains(Ui.na_getConfig()).mullions), [500, 700, 600]);
Ui.na_setConfig({ transoms: 1, transom_1_y_mm: 700 });
na_expect('top light typed over', Ui.na_applyDimensionEdit('transom', 1, '300').ok, true);
na_expect('transom stored as its bottom above the frame', Ui.na_getConfig().transom_1_y_mm, 830);
na_expect('the transom chain reads what was typed', na_segments(Generator.na_computeDimensionChains(Ui.na_getConfig()).transoms), [900, 300]);
na_expect('a segment the drawing does not have', Ui.na_applyDimensionEdit('transom', 5, '300').ok, false);

na_suite('Lead Line Margins hydration (a window saved before V2.2.0)');
Ui.na_setConfig({ leaded_margins_enabled: true, leaded_margin_x_mm: 30 });
na_expect('switched on in the dialog', Ui.na_getConfig().leaded_margins_enabled, true);
Ui.na_setConfig(na_window(), { fullConfig: true });
na_expect('an older window selected: off', Ui.na_getConfig().leaded_margins_enabled, false);
Ui.na_setConfig(na_window({ leaded_margins_enabled: true }), { fullConfig: true });
na_expect('a window saved with them on keeps them', Ui.na_getConfig().leaded_margins_enabled, true);
Ui.na_setConfig({ width_mm: 1500 });
na_expect('a partial update (Measure Opening) leaves them alone', Ui.na_getConfig().leaded_margins_enabled, true);

na_suite('CAD zoom and pan (Na__Viewport__Controls)');
const na_svg_el = na_fake_svg(100, 50, 600, 300);
const na_wrapper_el = na_fake_wrapper();
const na_box = { x: 0, y: 0, width: 1000, height: 1000 };
const na_state = { scale: 1, isPanning: false, didPan: false, lastMousePos: { x: 0, y: 0 }, panStartPos: { x: 0, y: 0 } };
let na_fits = 0;
Controls.na_setupPanZoom(na_wrapper_el, na_svg_el, na_box, na_state,
    () => Controls.na_updateViewBox(na_svg_el, na_box), { onZoomExtents: () => { na_fits += 1; } });
const na_fitter = () => Controls.na_windowResetFitter({ width_mm: 1800, height_mm: 1200 });
Controls.na_resetView(na_svg_el, na_box, na_state, null, na_fitter);
na_expect('fit records its width and clears the user view', [na_state.fitWidth, na_state.userView], [2200, false]);

const na_cursor = { clientX: 220, clientY: 110 };
const na_before = Controls.na_clientToSvg(na_svg_el, na_cursor.clientX, na_cursor.clientY);
na_wrapper_el.na_dispatch('wheel', Object.assign({ deltaY: -100, deltaMode: 0, preventDefault: () => {} }, na_cursor));
const na_in = Controls.na_clientToSvg(na_svg_el, na_cursor.clientX, na_cursor.clientY);
na_near('zoom in: the point under the cursor stays put (x)', na_in.x, na_before.x, 1e-6);
na_near('zoom in: the point under the cursor stays put (y)', na_in.y, na_before.y, 1e-6);
na_expect('zoom in: closer (narrower view)', na_box.width < 2200, true);
na_expect('zoom marks the view as the user\'s', na_state.userView, true);
na_wrapper_el.na_dispatch('wheel', Object.assign({ deltaY: 300, deltaMode: 0, preventDefault: () => {} }, na_cursor));
const na_out = Controls.na_clientToSvg(na_svg_el, na_cursor.clientX, na_cursor.clientY);
na_near('zoom out: still about the cursor, not the top left (x)', na_out.x, na_before.x, 1e-6);
na_near('zoom out: still about the cursor, not the top left (y)', na_out.y, na_before.y, 1e-6);
na_wrapper_el.na_dispatch('wheel', { deltaY: 3, deltaMode: 1, clientX: 400, clientY: 200, preventDefault: () => {} });
na_expect('line mode wheels (deltaMode 1) zoom too', na_state.scale < 1, true);
for (let step = 0; step < 200; step++) {
    na_wrapper_el.na_dispatch('wheel', { deltaY: -400, deltaMode: 0, clientX: 400, clientY: 200, preventDefault: () => {} });
}
na_near('zoom in stops at 1/60 of the fitted width', na_box.width, 2200 / 60, 1e-6);
for (let step = 0; step < 200; step++) {
    na_wrapper_el.na_dispatch('wheel', { deltaY: 400, deltaMode: 0, clientX: 400, clientY: 200, preventDefault: () => {} });
}
na_near('zoom out stops at 6 times the fitted width', na_box.width, 2200 * 6, 1e-6);

Controls.na_resetView(na_svg_el, na_box, na_state, null, na_fitter);
const na_grab = Controls.na_clientToSvg(na_svg_el, 300, 200);
na_wrapper_el.na_dispatch('mousedown', { button: 0, clientX: 300, clientY: 200, target: na_target(false), preventDefault: () => {} });
window.na_dispatch('mousemove', { clientX: 330, clientY: 190 });
window.na_dispatch('mousemove', { clientX: 380, clientY: 160 });
window.na_dispatch('mouseup', {});
const na_dropped = Controls.na_clientToSvg(na_svg_el, 380, 160);
na_near('drag: the drawing stays under the cursor (x)', na_dropped.x, na_grab.x, 1e-6);
na_near('drag: the drawing stays under the cursor (y)', na_dropped.y, na_grab.y, 1e-6);
na_expect('the click that ends a drag is still seen as a pan', na_state.didPan, true);
na_expect('the drag is over', na_state.isPanning, false);
const na_still = JSON.stringify(na_box);
na_wrapper_el.na_dispatch('mousedown', { button: 0, clientX: 300, clientY: 200, target: na_target(false), preventDefault: () => {} });
window.na_dispatch('mousemove', { clientX: 303, clientY: 202 });
window.na_dispatch('mouseup', {});
na_expect('a 3 px jitter is still a click: no pan', [na_state.didPan, JSON.stringify(na_box)], [false, na_still]);
na_wrapper_el.na_dispatch('mousedown', { button: 0, clientX: 300, clientY: 200, target: na_target(true), preventDefault: () => {} });
window.na_dispatch('mousemove', { clientX: 380, clientY: 160 });
window.na_dispatch('mouseup', {});
na_expect('a press on a dimension never pans', JSON.stringify(na_box), na_still);
na_wrapper_el.na_dispatch('dblclick', { target: na_target(false) });
na_expect('double click on empty canvas fits', na_fits, 1);
na_wrapper_el.na_dispatch('dblclick', { target: na_target(true) });
na_expect('double click on a casement, bar or dimension does not', na_fits, 1);
na_wrapper_el.na_dispatch('mousedown', { button: 1, clientX: 300, clientY: 200, target: na_target(false), preventDefault: () => {} });
window.na_dispatch('mouseup', {});
na_wrapper_el.na_dispatch('mousedown', { button: 1, clientX: 300, clientY: 200, target: na_target(false), preventDefault: () => {} });
window.na_dispatch('mouseup', {});
na_expect('middle button double press fits', na_fits, 2);

na_suite('A zoom survives edits only where asked (Na__Viewport__Instance)');
na_fake_elements['na-spec-wrapper-a'] = na_fake_wrapper();
na_fake_elements['na-spec-svg-a'] = na_fake_svg(0, 0, 600, 300);
na_fake_elements['na-spec-wrapper-b'] = na_fake_wrapper();
na_fake_elements['na-spec-svg-b'] = na_fake_svg(0, 0, 600, 300);
function na_instance(suffix, keepUserView) {
    return window.Na__Viewport__Instance.na_create({
        wrapperId: 'na-spec-wrapper-' + suffix, svgId: 'na-spec-svg-' + suffix,
        fitToContent: config => Controls.na_windowResetFitter(config),
        onRender: () => {}, keepUserView: keepUserView
    });
}
const na_keeper = na_instance('a', true);
const na_plain = na_instance('b', false);
na_keeper.na_render({ width_mm: 1800, height_mm: 1200 });
na_plain.na_render({ width_mm: 1800, height_mm: 1200 });
na_expect('first render fits', na_fake_elements['na-spec-svg-a'].getAttribute('viewBox'), '-200 -1400 2200 1600');
[['a', na_keeper], ['b', na_plain]].forEach(([suffix]) => {
    na_fake_elements['na-spec-wrapper-' + suffix].na_dispatch('wheel', { deltaY: -100, deltaMode: 0, clientX: 300, clientY: 150, preventDefault: () => {} });
});
const na_zoomed_a = na_fake_elements['na-spec-svg-a'].getAttribute('viewBox');
na_keeper.na_render({ width_mm: 1900, height_mm: 1200 });
na_plain.na_render({ width_mm: 1900, height_mm: 1200 });
na_expect('keepUserView: the zoom holds through an edit', na_fake_elements['na-spec-svg-a'].getAttribute('viewBox'), na_zoomed_a);
na_expect('default (door and cabinet tabs): refits as before', na_fake_elements['na-spec-svg-b'].getAttribute('viewBox'), '-200 -1400 2300 1600');
na_keeper.na_autoFitView({ width_mm: 1900, height_mm: 1200 });
na_expect('na_autoFitView leaves a user view alone', na_fake_elements['na-spec-svg-a'].getAttribute('viewBox'), na_zoomed_a);
na_keeper.na_releaseView();
na_keeper.na_render({ width_mm: 1900, height_mm: 1200 });
na_expect('released (another element): the next render fits', na_fake_elements['na-spec-svg-a'].getAttribute('viewBox'), '-200 -1400 2300 1600');
na_fake_elements['na-spec-wrapper-a'].na_dispatch('wheel', { deltaY: -100, deltaMode: 0, clientX: 300, clientY: 150, preventDefault: () => {} });
na_fake_elements['na-spec-wrapper-a'].na_dispatch('dblclick', { target: na_target(false) });
na_expect('double click fits the last rendered window', na_fake_elements['na-spec-svg-a'].getAttribute('viewBox'), '-200 -1400 2300 1600');
na_keeper.na_resetView({ width_mm: 1800, height_mm: 1200 });
na_expect('Reset View always fits', na_fake_elements['na-spec-svg-a'].getAttribute('viewBox'), '-200 -1400 2200 1600');

na_suite('Single lead lines clicked off (V2.2.1): keys and the preview');
na_expect('a line key is its cell key, the axis and its number', Generator.na_getLeadLineKey('1:0:0:0:0:0', 'h', 2), '1:0:0:0:0:0:h:2');
const na_lead_window = na_window(Object.assign({ leaded_glass_enabled: true, horizontal_leaded_bars: 6, vertical_leaded_bars: 3, leaded_width_mm: 6 }));
const na_valid_lines = Generator.na_collectValidLeadLineKeys(na_lead_window);
na_expect('valid keys: 3 lights x (6 + 3) lines', na_valid_lines.length, 27);
na_expect('valid keys include the first and last of a light',
    [na_valid_lines.includes('0:0:0:0:0:0:h:1'), na_valid_lines.includes('2:0:0:0:0:0:v:3'), na_valid_lines.includes('0:0:0:0:0:0:h:7')], [true, true, false]);
const na_strip_svg = Generator.na_generateWindowSvg(na_lead_window);
na_expect('one click strip per line', (na_strip_svg.match(/class="na-lead-line-click-target"/g) || []).length, 27);
na_expect('strips carry their keys', /data-lead-key="1:0:0:0:0:0:v:2"/.test(na_strip_svg), true);
const na_off = na_preview_leads(Object.assign({}, na_lead_window, { removed_lead_lines: ['0:0:0:0:0:0:h:1', '1:0:0:0:0:0:v:2'] }));
const na_on = na_preview_leads(na_lead_window);
na_expect('a line clicked off is not drawn (h: one row fewer in the left light)', na_off.h.length, na_on.h.length - 1);
na_expect('the vertical clicked off is the centre light\'s middle one', na_on.v.filter(x => !na_off.v.includes(x)), [900]);
const na_bottom_row = na_r3(120 + 970 / 7);
na_expect('the bottom row: drawn in all three lights, then only in the other two',
    [na_on.h.filter(y => y === na_bottom_row).length, na_off.h.filter(y => y === na_bottom_row).length], [3, 2]);
const na_off_svg = Generator.na_generateWindowSvg(Object.assign({}, na_lead_window, { removed_lead_lines: ['1:0:0:0:0:0:v:2'] }));
na_expect('its click strip stays, so it can be clicked back on', /data-lead-key="1:0:0:0:0:0:v:2"/.test(na_off_svg), true);
na_expect('door previews never get strips (sliding)', /na-lead-line-click-target/.test(window.Na__ExtSlide__ElevationGenerator.na_generate_sliding_svg(
    na_window({ sliding_mode: true, width_mm: 3000, height_mm: 2100, leaded_glass_enabled: true, horizontal_leaded_bars: 2 }))), false);

na_suite('Single lead lines clicked off: the panel logic');
Ui.na_setConfig(na_window({ leaded_glass_enabled: true, horizontal_leaded_bars: 6, vertical_leaded_bars: 3, removed_lead_lines: [] }));
Ui.na_toggleLeadLineRemoval('0:0:0:0:0:0:h:1');
na_expect('click: the line is off', Ui.na_getConfig().removed_lead_lines, ['0:0:0:0:0:0:h:1']);
Ui.na_toggleLeadLineRemoval('0:0:0:0:0:0:h:1');
na_expect('click again: back on', Ui.na_getConfig().removed_lead_lines, []);
Ui.na_toggleLeadLineRemoval('0:0:0:0:0:0:h:6');
Ui.na_toggleLeadLineRemoval('1:0:0:0:0:0:v:3');
Ui.na_setConfig({ horizontal_leaded_bars: 4 });
na_expect('fewer lines: keys past the new count drop, the rest stay', Ui.na_getConfig().removed_lead_lines, ['1:0:0:0:0:0:v:3']);
Ui.na_setConfig({ leaded_glass_enabled: false });
Ui.na_toggleLeadLineRemoval('0:0:0:0:0:0:h:1');
na_expect('leaded glass off: clicks do nothing', Ui.na_getConfig().removed_lead_lines, ['1:0:0:0:0:0:v:3']);
Ui.na_setConfig({ leaded_glass_enabled: true });
Ui.na_resetHiddenElements();
na_expect('Reset Elements brings every line back', Ui.na_getConfig().removed_lead_lines, []);
Ui.na_toggleLeadLineRemoval('0:0:0:0:0:0:h:2');
Ui.na_setConfig(na_window({ leaded_glass_enabled: true, horizontal_leaded_bars: 6 }), { fullConfig: true });
na_expect('another window saved before V2.2.1 is selected: it has every line', Ui.na_getConfig().removed_lead_lines, []);

na_suite('Single lead lines clicked off: the click (Na__Viewport__Controls)');
const na_click_svg = na_event_target({ removeEventListener: () => {} });
const na_click_state = { didPan: false };
let na_clicked_line = null;
Controls.na_setupCasementClickTargets(na_click_svg, na_click_state, null, null, null, null, (key) => { na_clicked_line = key; });
const na_strip = { classList: { contains: (name) => name === 'na-lead-line-click-target' }, getAttribute: () => '2:0:0:0:0:0:h:3' };
na_click_svg.na_dispatch('click', { target: na_strip });
na_expect('a click on a strip hands over its key', na_clicked_line, '2:0:0:0:0:0:h:3');
na_clicked_line = null;
na_click_state.didPan = true;
na_click_svg.na_dispatch('click', { target: na_strip });
na_expect('the click that ends a pan does not', na_clicked_line, null);

na_suite('X and Y margins switched on their own (V2.2.2)');
const na_margins_on = { leaded_margins_enabled: true, leaded_margin_x_mm: 30, leaded_margin_y_mm: 40 };
na_expect('Y only: X comes back null', Generator.na_resolveLeadMargins(Object.assign({ leaded_margin_x_enabled: false }, na_margins_on)), { x: null, y: 40 });
na_expect('X only: Y comes back null', Generator.na_resolveLeadMargins(Object.assign({ leaded_margin_y_enabled: false }, na_margins_on)), { x: 30, y: null });
na_expect('both switched off: no margins at all',
    Generator.na_resolveLeadMargins(Object.assign({ leaded_margin_x_enabled: false, leaded_margin_y_enabled: false }, na_margins_on)), null);
na_expect('no switches (saved by V2.2.0 or V2.2.1): both on', Generator.na_resolveLeadMargins(na_margins_on), { x: 30, y: 40 });
const na_y_only = na_preview_leads(na_window(Object.assign({ leaded_glass_enabled: true, horizontal_leaded_bars: 6, vertical_leaded_bars: 3,
    leaded_width_mm: 6, leaded_margin_x_enabled: false, leaded_margin_y_enabled: true }, na_margins_on)));
na_expect('Y only: the rows sit 40 in from top and bottom', na_y_only.h.filter((y, i, all) => all.indexOf(y) === i), [160, 338, 516, 694, 872, 1050]);
na_expect('Y only: the verticals divide each light evenly, as with margins off', na_y_only.v, na_even.v);
const na_x_only = na_preview_leads(na_window(Object.assign({ leaded_glass_enabled: true, horizontal_leaded_bars: 6, vertical_leaded_bars: 3,
    leaded_width_mm: 6, leaded_margin_x_enabled: true, leaded_margin_y_enabled: false }, na_margins_on)));
na_expect('X only: the verticals sit 30 in from each side', na_x_only.v, [120, 320, 520, 700, 900, 1100, 1280, 1480, 1680]);
na_expect('X only: the rows divide evenly, as with margins off', na_x_only.h, na_even.h);

Ui.na_setConfig(na_window(Object.assign({ leaded_glass_enabled: true }, na_margins_on)), { fullConfig: true });
na_expect('a window saved by V2.2.1 with margins on loads with both directions on',
    [Ui.na_getConfig().leaded_margin_x_enabled, Ui.na_getConfig().leaded_margin_y_enabled], [true, true]);
Ui.na_setConfig(na_window(), { fullConfig: true });
na_expect('a window without margins loads as the new default: X off, Y on',
    [Ui.na_getConfig().leaded_margin_x_enabled, Ui.na_getConfig().leaded_margin_y_enabled], [false, true]);
Ui.na_setConfig(na_window(Object.assign({ leaded_margin_x_enabled: false, leaded_margin_y_enabled: true }, na_margins_on)), { fullConfig: true });
na_expect('a window saved with Y only keeps Y only',
    [Ui.na_getConfig().leaded_margin_x_enabled, Ui.na_getConfig().leaded_margin_y_enabled], [false, true]);

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);
