/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - PER CASEMENT SETTINGS + ALIGNED LEAD SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__CasementOverrides__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for V1.8.0 - Advanced Casement Controls >
                Per Casement Settings (each casement's own stiles, rails and
                Casement Frame Inset) and Leaded Glass > Align Lead Lines
                Across Casements.
   CREATED    : 26-Oct-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__CasementOverrides__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHAT IT DRIVES
   The SHIPPED modules, unmodified: the shared Controls engine, the window UI
   config, MullionMath, CasementMath, GlazebarMath, the SVG generator, the
   validator, the JS DXF exporter and MainUiLogic, against a small DOM stub
   that holds just the Per Casement Settings container. Change handlers are
   captured where the Events module would bind them and driven the way a
   click or a drag does.

   THE REFERENCE WINDOW
   The cottage window that prompted the feature: 1800 x 1200, 50 frame, two
   40 mullions, so three 540 lights, window-wide casements of 40 stiles,
   60 top rail, 70 bottom rail, leaded 6 x 3. The centre casement is given
   70 stiles, a 100 top rail, a 90 bottom rail and sits 20 proud. The Ruby
   side is held to the same hand-worked numbers by the stand-in harness.

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

// HELPER FUNCTION | Read One Shipped Source File
// ------------------------------------------------------------
function na_read(relativePath) {
    return fs.readFileSync(path.join(NA_MODULES, relativePath), 'utf8');
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Round to a Thousandth so Float Noise Never Fails a Test
// ------------------------------------------------------------
function na_round(value) {
    return Math.round(value * 1000) / 1000;
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Stub
// -----------------------------------------------------------------------------

// Only the Per Casement Settings dropdown exists: its wrapper (for the
// show / hide) and its content (which counts every rebuild). Every other
// lookup misses, so the UI logic updates only its config.
let na_onControlChange = null;                                       // <-- The main control-change handler
const na_overrideHandlers = {};                                      // <-- Per-casement control id -> handler
let na_contentWrites = 0;

const na_wrapper = { style: { display: '' } };
const na_content = {
    _html: '',
    get innerHTML() { return this._html; },
    set innerHTML(value) { this._html = value; na_contentWrites += 1; }
};

function na_container() {
    return { innerHTML: '', insertAdjacentHTML: () => {} };
}

global.window   = global;
global.document = {
    getElementById   : (id) => {
        if (String(id).indexOf('na-controls-') === 0) return na_container();
        if (id === 'casement_individual_controls-content') return na_content;
        return null;
    },
    querySelector    : (selector) => (selector === '[data-control-id="casement_individual_controls"]' ? na_wrapper : null),
    querySelectorAll : () => [],
    addEventListener : () => {},
    createElementNS  : () => ({ setAttribute: () => {}, appendChild: () => {} })
};
window.Na__Ui__Events = {
    na_attachEventListeners: (config, callback) => {
        if (String(config.id).indexOf('casement_override__') === 0) {
            na_overrideHandlers[config.id] = callback;
            return;
        }
        na_onControlChange = callback;
    }
};
const na_console_error = console.error;
console.error = (message, ...rest) => {                              // <-- No viewport is built here; keep every other error
    if (String(message).indexOf('[NA_VIEWPORT]') === 0) return;
    na_console_error(message, ...rest);
};

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Load the Shipped Modules
// -----------------------------------------------------------------------------

const NA_SOURCES = [
    '01__AppCore/Na__AssemblyStudio__AppCore__UiSystem__Controls__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__Config__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__MullionMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__CasementMath__.js',
    '05__Viewport__2dPreviewEngine/Na__AssemblyStudio__Viewport__Validation__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Export__Dxf__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__MainUiLogic__.js'
];

// Each shipped file declares top-level `const`s, which would collide across a
// shared eval scope, so every source is evaluated in its own function scope.
const na_console_log = console.log;
console.log = () => {};                                              // <-- Silence the dialog's own init logging
NA_SOURCES.forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + na_read(relativePath) + '\n})()');
});

const Ui       = window.Na_DynamicUI;
const Casement = window.Na__CasementMath;
const Svg      = window.Na__Viewport__SvgGenerator;
const Validate = window.Na__Viewport__Validation;
const Dxf      = window.Na__Export__Dxf;
Ui.na_init();
console.log = na_console_log;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Fixtures
// -----------------------------------------------------------------------------

const NA_WINDOW = {
    width_mm: 1800, height_mm: 1200, frame_thickness_mm: 50, advanced_frame_controls: false,
    casement_width_mm: 65, casement_sizes_individual: true,
    casement_top_rail_mm: 60, casement_bottom_rail_mm: 70,
    casement_left_stile_mm: 40, casement_right_stile_mm: 40,
    casement_depth_mm: 55, casement_inset_mm: 10, casements_per_opening: 1,
    mullions: 2, mullion_width_mm: 40, transoms: 0, transom_width_mm: 40,
    horizontal_glaze_bars: 0, vertical_glaze_bars: 0, glaze_bar_width_mm: 25,
    leaded_glass_enabled: true, horizontal_leaded_bars: 6, vertical_leaded_bars: 3,
    leaded_width_mm: 6, leaded_centre_lines_only: false, leaded_disabled_cells: [],
    removed_casements: [], removed_transom_segments: [], removed_glazebars: [],
    show_casements: true, sliding_sash_window: false, has_cill: true, cill_height_mm: 50,
    show_dimensions: false
};

const NA_CENTRE = {
    enabled: true, left_stile_mm: 70, right_stile_mm: 70,
    top_rail_mm: 100, bottom_rail_mm: 90, inset_mm: -20
};

function na_window(extra) {
    return Object.assign({}, NA_WINDOW, extra || {});
}

// HELPER FUNCTION | Every <rect> the SVG Generator Drew, in y-up Millimetres
// ------------------------------------------------------------
function na_rects(svg) {
    const rects = [];
    const pattern = /<rect x="([-\d.e]+)" y="([-\d.e]+)" width="([-\d.e]+)" height="([-\d.e]+)"\s+fill="([^"]*)" stroke="([^"]*)" stroke-width="([^"]*)"\/>/g;
    let match;
    while ((match = pattern.exec(svg)) !== null) {
        const h = Number(match[4]);
        rects.push({
            x: Number(match[1]), y: -Number(match[2]) - h, w: Number(match[3]), h: h,
            fill: match[5], stroke: match[6], strokeWidth: match[7]
        });
    }
    return rects;
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Horizontal Lead Centres Inside One Light, Bottom Up
// ------------------------------------------------------------
// Lead ribbons are the 0.4-stroke rects; a horizontal one is the 6mm tall.
function na_horizontalLeads(svg, lightLeft, lightRight) {
    return na_rects(svg)
        .filter(r => r.strokeWidth === '0.4' && r.h === 6 && r.x >= lightLeft && r.x < lightRight)
        .map(r => na_round(r.y + r.h / 2))
        .sort((a, b) => a - b);
}

function na_verticalLeads(svg, lightLeft, lightRight) {
    return na_rects(svg)
        .filter(r => r.strokeWidth === '0.4' && r.w === 6 && r.x >= lightLeft && r.x < lightRight)
        .map(r => na_round(r.x + r.w / 2))
        .sort((a, b) => a - b);
}
// ---------------------------------------------------------------

// Window-wide glass of every light runs from 50 + 70 = 120 to 1150 - 60 = 1090.
const NA_PITCH = 970 / 7;
const NA_SHARED_HEIGHTS = [1, 2, 3, 4, 5, 6].map(k => na_round(120 + NA_PITCH * k));

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | CasementMath - Sizes
// -----------------------------------------------------------------------------

na_suite('CasementMath: window-wide sizes');

na_expect('Individual sizes read each member',
    Casement.na_resolveGlobalCasementSizes(NA_WINDOW),
    { top_rail_mm: 60, bottom_rail_mm: 70, left_stile_mm: 40, right_stile_mm: 40, inset_mm: 10, overridden: false });
na_expect('Shared sizes use Casement Width for all four',
    Casement.na_resolveGlobalCasementSizes(na_window({ casement_sizes_individual: false })),
    { top_rail_mm: 65, bottom_rail_mm: 65, left_stile_mm: 65, right_stile_mm: 65, inset_mm: 10, overridden: false });
na_expect('A zero inset stays zero',
    Casement.na_resolveGlobalCasementSizes(na_window({ casement_inset_mm: 0 })).inset_mm, 0);
na_expect('A missing inset defaults to 10',
    Casement.na_resolveGlobalCasementSizes(na_window({ casement_inset_mm: undefined })).inset_mm, 10);

na_suite('CasementMath: one casement\'s own settings');

const NA_GLOBAL = Casement.na_resolveGlobalCasementSizes(NA_WINDOW);
na_expect('Switched-on override replaces all five',
    Casement.na_applyCasementOverride(NA_GLOBAL, { '1:0:0': NA_CENTRE }, '1:0:0'),
    { top_rail_mm: 100, bottom_rail_mm: 90, left_stile_mm: 70, right_stile_mm: 70, inset_mm: -20, overridden: true });
na_expect('Switched-off override is ignored',
    Casement.na_applyCasementOverride(NA_GLOBAL, { '1:0:0': Object.assign({}, NA_CENTRE, { enabled: false }) }, '1:0:0'),
    NA_GLOBAL);
na_expect('Another casement is untouched',
    Casement.na_applyCasementOverride(NA_GLOBAL, { '1:0:0': NA_CENTRE }, '0:0:0'), NA_GLOBAL);
na_expect('A missing field falls back to the window-wide value',
    Casement.na_applyCasementOverride(NA_GLOBAL, { '1:0:0': { enabled: true, top_rail_mm: 250 } }, '1:0:0'),
    { top_rail_mm: 250, bottom_rail_mm: 70, left_stile_mm: 40, right_stile_mm: 40, inset_mm: 10, overridden: true });
na_expect('Members never go below zero, the inset may',
    Casement.na_applyCasementOverride(NA_GLOBAL, { k: { enabled: true, left_stile_mm: -5, inset_mm: -60 } }, 'k'),
    { top_rail_mm: 60, bottom_rail_mm: 70, left_stile_mm: 0, right_stile_mm: 40, inset_mm: -60, overridden: true });
na_expect('Non-numeric values are ignored',
    Casement.na_applyCasementOverride(NA_GLOBAL, { k: { enabled: true, top_rail_mm: '99', left_stile_mm: null } }, 'k').top_rail_mm, 60);

na_suite('CasementMath: which products take overrides');

na_expect('Casement window', Casement.na_supportsCasementOverrides(NA_WINDOW), true);
na_expect('Sliding sash', Casement.na_supportsCasementOverrides(na_window({ sliding_sash_window: true })), false);
na_expect('Show Casements off', Casement.na_supportsCasementOverrides(na_window({ show_casements: false })), false);
['double_door_mode', 'ext_single_door_mode', 'sliding_mode', 'multifold_mode'].forEach(mode => {
    na_expect('Door product ' + mode, Casement.na_supportsCasementOverrides(na_window({ [mode]: true })), false);
});
na_expect('Resolve ignores overrides on a sliding sash',
    Casement.na_resolveCasementSizes(na_window({ sliding_sash_window: true, casement_overrides: { '0:0:0': NA_CENTRE } }), 0, 0, 0).overridden,
    false);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | CasementMath - Names and Numbering
// -----------------------------------------------------------------------------

na_suite('CasementMath: names in reading order');

function na_labels(config) {
    return Casement.na_enumerateCasements(config).map(casement => casement.label);
}

na_expect('Three lights', na_labels(NA_WINDOW),
    ['Casement 1 (Left Light)', 'Casement 2 (Centre Light)', 'Casement 3 (Right Light)']);
na_expect('One light, one casement', na_labels(na_window({ mullions: 0 })), ['Casement 1']);
na_expect('Two lights', na_labels(na_window({ mullions: 1 })),
    ['Casement 1 (Left Light)', 'Casement 2 (Right Light)']);
na_expect('Five lights name by number', na_labels(na_window({ mullions: 4, width_mm: 3000 })).slice(3),
    ['Casement 4 (Light 4)', 'Casement 5 (Light 5)']);
na_expect('A transom reads the top row first',
    na_labels(na_window({ mullions: 1, transoms: 1, transom_1_y_mm: 700 })),
    ['Casement 1 (Left Light, Top)', 'Casement 2 (Right Light, Top)',
     'Casement 3 (Left Light, Bottom)', 'Casement 4 (Right Light, Bottom)']);
na_expect('Two casements per opening are leaves',
    na_labels(na_window({ mullions: 0, casements_per_opening: 2 })),
    ['Casement 1 (Leaf 1)', 'Casement 2 (Leaf 2)']);

const NA_LISTED = Casement.na_enumerateCasements(na_window({ removed_casements: ['1:0:0'], casement_overrides: { '2:0:0': NA_CENTRE } }));
na_expect('A removed casement keeps its number', NA_LISTED.map(c => [c.number, c.key, c.removed]),
    [[1, '0:0:0', false], [2, '1:0:0', true], [3, '2:0:0', false]]);
na_expect('Listed sizes carry the override', NA_LISTED[2].sizes.overridden, true);
na_expect('Centre light panel geometry', [NA_LISTED[1].x, NA_LISTED[1].y, NA_LISTED[1].width, NA_LISTED[1].height], [630, 50, 540, 1100]);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | SVG Preview
// -----------------------------------------------------------------------------

na_suite('Preview: nothing moves without overrides');

na_expect('Alignment on draws the same window as off (no overrides)',
    Svg.na_generateWindowSvg(na_window({ leaded_global_alignment: true })),
    Svg.na_generateWindowSvg(na_window({ leaded_global_alignment: false })));
na_expect('Alignment on draws a sliding sash exactly as off',
    Svg.na_generateWindowSvg(na_window({ sliding_sash_window: true, leaded_global_alignment: true, mullions: 0 })),
    Svg.na_generateWindowSvg(na_window({ sliding_sash_window: true, mullions: 0 })));
na_expect('A switched-off override draws nothing new',
    Svg.na_generateWindowSvg(na_window({ casement_overrides: { '1:0:0': Object.assign({}, NA_CENTRE, { enabled: false }) } })),
    Svg.na_generateWindowSvg(NA_WINDOW));
na_expect('Left light lead divides its own glass',
    na_horizontalLeads(Svg.na_generateWindowSvg(NA_WINDOW), 50, 590), NA_SHARED_HEIGHTS);

na_suite('Preview: the centre casement on its own settings');

const NA_ALIGNED = Svg.na_generateWindowSvg(na_window({ casement_overrides: { '1:0:0': NA_CENTRE }, leaded_global_alignment: true }));
const NA_CENTRE_MEMBERS = na_rects(NA_ALIGNED).filter(r => r.stroke === '#000' && r.strokeWidth === '0.5' && r.x >= 630 && r.x < 1170);
na_expect('Centre left stile is 70 wide', NA_CENTRE_MEMBERS.some(r => r.x === 630 && r.w === 70 && r.h === 1100), true);
na_expect('Centre right stile is 70 wide', NA_CENTRE_MEMBERS.some(r => r.x === 1100 && r.w === 70), true);
na_expect('Centre top rail is 100 deep', NA_CENTRE_MEMBERS.some(r => r.x === 700 && r.h === 100 && r.y === 1050), true);
na_expect('Centre bottom rail is 90 deep', NA_CENTRE_MEMBERS.some(r => r.x === 700 && r.h === 90 && r.y === 50), true);
na_expect('Centre lead runs level with the left light', na_horizontalLeads(NA_ALIGNED, 630, 1170), NA_SHARED_HEIGHTS);
na_expect('Right light lead unchanged', na_horizontalLeads(NA_ALIGNED, 1210, 1750), NA_SHARED_HEIGHTS);
na_expect('Centre verticals follow its light\'s window-wide grid', na_verticalLeads(NA_ALIGNED, 630, 1170),
    [1, 2, 3].map(k => na_round(670 + 115 * k)));

const NA_OWN = Svg.na_generateWindowSvg(na_window({ casement_overrides: { '1:0:0': NA_CENTRE }, leaded_global_alignment: false }));
na_expect('Alignment off: centre lead divides its own glass', na_horizontalLeads(NA_OWN, 630, 1170),
    [1, 2, 3, 4, 5, 6].map(k => na_round(140 + (910 / 7) * k)));

const NA_DEEP_RAIL = Svg.na_generateWindowSvg(na_window({ casement_overrides: { '1:0:0': { enabled: true, top_rail_mm: 250 } }, leaded_global_alignment: true }));
na_expect('A deep top rail hides the top line, the rest stay level', na_horizontalLeads(NA_DEEP_RAIL, 630, 1170), NA_SHARED_HEIGHTS.slice(0, 5));

const NA_FIXED = Svg.na_generateWindowSvg(na_window({ removed_casements: ['1:0:0'], leaded_global_alignment: true }));
na_expect('A fixed centre light lines up with its neighbours', na_horizontalLeads(NA_FIXED, 630, 1170), NA_SHARED_HEIGHTS);
const NA_FIXED_OWN = Svg.na_generateWindowSvg(na_window({ removed_casements: ['1:0:0'], leaded_global_alignment: false }));
na_expect('Alignment off: a fixed light divides its own glass, as before', na_horizontalLeads(NA_FIXED_OWN, 630, 1170),
    [1, 2, 3, 4, 5, 6].map(k => na_round(50 + (1100 / 7) * k)));

na_suite('Preview: casement numbers');

function na_badges(config) {
    return (Svg.na_generateWindowSvg(config).match(/class="na-casement-number-badge"/g) || []).length;
}
na_expect('No numbers while the dropdown is shut', na_badges(NA_WINDOW), 0);
na_expect('No numbers with only the outer dropdown open', na_badges(na_window({ advanced_casement_controls: true })), 0);
na_expect('One number per casement with both open',
    na_badges(na_window({ advanced_casement_controls: true, casement_individual_controls: true })), 3);
na_expect('A removed casement has no number',
    na_badges(na_window({ advanced_casement_controls: true, casement_individual_controls: true, removed_casements: ['0:0:0'] })), 2);
na_expect('Sliding sash shows no numbers',
    na_badges(na_window({ advanced_casement_controls: true, casement_individual_controls: true, sliding_sash_window: true })), 0);
na_expect('Overridden casement is filled',
    Svg.na_generateWindowSvg(na_window({ advanced_casement_controls: true, casement_individual_controls: true, casement_overrides: { '1:0:0': NA_CENTRE } }))
        .indexOf('fill="#4a90d9" stroke="#4a90d9"') !== -1, true);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Validation and DXF
// -----------------------------------------------------------------------------

na_suite('Validation');

na_expect('Reference window is valid', Validate.na_validateConfig(na_window({ casement_overrides: { '1:0:0': NA_CENTRE } })).errors, []);
na_expect('Stiles wider than the light are refused',
    Validate.na_validateConfig(na_window({ casement_overrides: { '1:0:0': { enabled: true, left_stile_mm: 250, right_stile_mm: 250 } } })).errors,
    ['Casement 2 (Centre Light) is too narrow for its own stiles']);
na_expect('Rails taller than the light are refused',
    Validate.na_validateConfig(na_window({ casement_overrides: { '1:0:0': { enabled: true, top_rail_mm: 250, bottom_rail_mm: 500 } }, height_mm: 850 })).errors,
    ['Casement 2 (Centre Light) is too short for its own rails']);
na_expect('A switched-off override never blocks',
    Validate.na_validateConfig(na_window({ casement_overrides: { '1:0:0': { enabled: false, left_stile_mm: 250, right_stile_mm: 250 } } })).errors, []);
na_expect('A removed casement\'s override never blocks',
    Validate.na_validateConfig(na_window({ removed_casements: ['1:0:0'], casement_overrides: { '1:0:0': { enabled: true, left_stile_mm: 250, right_stile_mm: 250 } } })).errors, []);

na_suite('JS DXF');

function na_dxfVerticalXs(dxf) {
    const tokens = dxf.split('\n');
    const xs = [];
    for (let i = 0; i < tokens.length - 1; i += 1) {
        if (tokens[i] !== '0' || tokens[i + 1] !== 'LINE') continue;
        const read = (code) => Number(tokens[tokens.indexOf(code, i + 2) + 1]);
        if (read('10') === read('11')) xs.push(read('10'));
    }
    return xs;
}
const NA_DXF_ALIGNED = na_dxfVerticalXs(Dxf.na_exportDxf(na_window({ casement_overrides: { '1:0:0': NA_CENTRE } })));
const NA_DXF_SHARED = na_dxfVerticalXs(Dxf.na_exportDxf(NA_WINDOW));
na_expect('DXF draws the centre 70 stile edge', NA_DXF_ALIGNED.includes(700), true);
na_expect('DXF has no 40 stile edge in the centre any more', NA_DXF_ALIGNED.includes(670), false);
na_expect('DXF of the shared window still has it', NA_DXF_SHARED.includes(670), true);
na_expect('DXF with a switched-off override is the shared window',
    Dxf.na_exportDxf(na_window({ casement_overrides: { '1:0:0': Object.assign({}, NA_CENTRE, { enabled: false }) } })),
    Dxf.na_exportDxf(NA_WINDOW));

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | MainUiLogic - The Per Casement Settings Dropdown
// -----------------------------------------------------------------------------

na_suite('Dialog: building the dropdown');

na_expect('Real control-change handler captured', typeof na_onControlChange, 'function');
na_onControlChange('mullions', 2);
na_expect('Three groups, named in order', (na_content.innerHTML.match(/<span class="na-control-label">Casement \d[^<]*<\/span>/g) || [])
    .map(span => span.replace(/<[^>]+>/g, '')),
    ['Casement 1 (Left Light)', 'Casement 2 (Centre Light)', 'Casement 3 (Right Light)']);
na_expect('Every casement starts on the window-wide settings', Ui.na_getConfig().casement_overrides, {});
na_expect('Handlers bound for every switch and slider', Object.keys(na_overrideHandlers).filter(id => id.indexOf('__1_0_0__') !== -1).sort(),
    ['casement_override__1_0_0__bottom_rail_mm', 'casement_override__1_0_0__enabled', 'casement_override__1_0_0__inset_mm',
     'casement_override__1_0_0__left_stile_mm', 'casement_override__1_0_0__right_stile_mm', 'casement_override__1_0_0__top_rail_mm']);
na_expect('Dropdown shown for a casement window', na_wrapper.style.display, '');

na_suite('Dialog: switching a casement on and adjusting it');

na_onControlChange('casement_sizes_individual', true);
na_onControlChange('casement_top_rail_mm', 60);
na_onControlChange('casement_bottom_rail_mm', 70);
na_overrideHandlers['casement_override__1_0_0__enabled']('casement_override__1_0_0__enabled', true);
na_expect('Switching on seeds the window-wide sizes', Ui.na_getConfig().casement_overrides['1:0:0'],
    { enabled: true, left_stile_mm: 40, right_stile_mm: 40, top_rail_mm: 60, bottom_rail_mm: 70, inset_mm: 10 });
na_expect('It is marked as on', (na_content.innerHTML.match(/na-casement-override--active/g) || []).length, 1);
na_expect('Its sliders show, the other two stay folded away',
    (na_content.innerHTML.match(/na-casement-override__fields" style="display:none;"/g) || []).length, 2);

const NA_WRITES_BEFORE_DRAG = na_contentWrites;
na_overrideHandlers['casement_override__1_0_0__top_rail_mm']('casement_override__1_0_0__top_rail_mm', 100);
na_overrideHandlers['casement_override__1_0_0__inset_mm']('casement_override__1_0_0__inset_mm', -20);
na_expect('A slider writes its own field', Ui.na_getConfig().casement_overrides['1:0:0'].top_rail_mm, 100);
na_expect('The inset takes a negative', Ui.na_getConfig().casement_overrides['1:0:0'].inset_mm, -20);
na_expect('Dragging never rebuilds the dropdown under the cursor', na_contentWrites, NA_WRITES_BEFORE_DRAG);

na_overrideHandlers['casement_override__1_0_0__enabled']('casement_override__1_0_0__enabled', false);
na_expect('Switching off keeps its values', Ui.na_getConfig().casement_overrides['1:0:0'],
    { enabled: false, left_stile_mm: 40, right_stile_mm: 40, top_rail_mm: 100, bottom_rail_mm: 70, inset_mm: -20 });
na_onControlChange('casement_top_rail_mm', 80);
na_overrideHandlers['casement_override__1_0_0__enabled']('casement_override__1_0_0__enabled', true);
na_expect('Switching back on restores them, not the new window-wide rail', Ui.na_getConfig().casement_overrides['1:0:0'].top_rail_mm, 100);

na_suite('Dialog: layout changes');

na_onControlChange('ui_window_type', 'SlidingSash');
na_expect('Hidden for a sliding sash', na_wrapper.style.display, 'none');
na_onControlChange('ui_window_type', 'Casement');
na_expect('Back for a casement window', na_wrapper.style.display, '');
na_onControlChange('show_casements', false);
na_expect('Hidden with Show Casements off', na_wrapper.style.display, 'none');
na_onControlChange('show_casements', true);
na_onControlChange('mullions', 1);
na_expect('Two lights, two groups', (na_content.innerHTML.match(/Casement \d \((Left|Right) Light\)/g) || []).length, 2);
na_expect('The stored override survives the light count dropping', Ui.na_getConfig().casement_overrides['1:0:0'].top_rail_mm, 100);
na_onControlChange('mullions', 2);

na_suite('Dialog: loading saved windows');

Ui.na_setConfig({ width_mm: 1500 });
na_expect('A partial update (a measurement) keeps the overrides', Ui.na_getConfig().casement_overrides['1:0:0'].enabled, true);

const NA_OLD_WINDOW = na_window();
delete NA_OLD_WINDOW.casement_overrides;
delete NA_OLD_WINDOW.leaded_global_alignment;
Ui.na_setConfig(Object.assign({}, NA_OLD_WINDOW), { fullConfig: true });
na_expect('A window saved before V1.8.0 does not inherit the last window\'s overrides', Ui.na_getConfig().casement_overrides, {});
na_expect('A window saved before V1.8.0 keeps pane-by-pane lead', Ui.na_getConfig().leaded_global_alignment, false);

Ui.na_setConfig(na_window({ casement_overrides: { '2:0:0': NA_CENTRE }, leaded_global_alignment: true }), { fullConfig: true });
na_expect('A V1.8.0 window loads its own overrides', Ui.na_getConfig().casement_overrides, { '2:0:0': NA_CENTRE });
na_expect('And its alignment', Ui.na_getConfig().leaded_global_alignment, true);
na_expect('The dropdown is rebuilt for it', /casement_override__2_0_0__top_rail_mm-slider"\s+min="20" max="250" step="5" value="100"/.test(na_content.innerHTML), true);
na_expect('A new dialog defaults alignment on', window.NA_GLAZEBAR_CONFIG
    .find(item => item.id === 'leaded_glass_controls').children
    .find(child => child.id === 'leaded_global_alignment').default, true);

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);
