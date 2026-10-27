/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - WINDOW BOARD SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__WindowBoard__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for the V1.9.0 window board - the Include
                Window Board toggle and its WINDOW BOARD section, the 2D
                preview outline, the three nosing assets, and Ruby / JS
                default parity.
   CREATED    : 26-Oct-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__WindowBoard__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHAT IT COVERS:
   - The SHIPPED control configs, MainUiLogic and Bridge run unmodified
     against a small DOM stub that records each section's and control's
     display, so the show / hide rules are checked as the dialog applies them.
   - A window saved before V1.9.0 (no window_board_enabled key) loads with
     the board off, whatever the previous window had.
   - The SVG generator draws the board outline under the frame, one board
     thickness past each side when the nosing is returned.
   - Each nosing asset parses, declares its type, and is the thickness and
     shape the builder expects. Type 01 must keep the Profile Path Tracer
     nose it was converted from (PRF90021), checked when that plugin sits
     beside this one.

   The 3D solid is not built here; its face layout is proved in SketchUp's
   Ruby (see the V1.9.0 DEVLOG entry).

   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');


// -----------------------------------------------------------------------------
// REGION | Harness
// -----------------------------------------------------------------------------

const NA_ROOT    = path.resolve(__dirname, '..');
const NA_MODULES = path.join(NA_ROOT, '02__Src__AppModules');
const NA_BOARDS  = path.join(NA_ROOT, '04__Data__AssetLibrary', 'Windows__WindowBoards__');
const NA_PPT_PRF90021 = path.resolve(NA_ROOT, '..', 'Na__ProfileTools__ProfilePathTracer__Modules__',
    '04__Data__ProfileLibrary', 'PRF90021__Vale__InteriorJoinery__WindowBoard__t30mm_x_d190mm__.json');

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
// REGION | DOM Stub That Records Visibility
// -----------------------------------------------------------------------------

// Every [data-control-id] wrapper and the WINDOW BOARD section are stub
// elements whose style.display the UI logic writes; every other lookup
// misses, so only config state and visibility are exercised.
let na_onControlChange = null;
const na_controls = {};

function na_stubElement(display) {
    return {
        style            : { display: display || '' },
        dataset          : {},
        classList        : { add: () => {}, remove: () => {}, toggle: () => {}, contains: () => false },
        querySelector    : () => null,
        querySelectorAll : () => [],
        setAttribute     : () => {},
        getAttribute     : () => null,
        addEventListener : () => {}
    };
}

const na_windowBoardSection = na_stubElement('none');                // <-- Ships hidden in the HTML

function na_container() {
    return { innerHTML: '', insertAdjacentHTML: () => {} };
}

global.window   = global;
global.document = {
    getElementById   : (id) => {
        if (String(id).indexOf('na-controls-') === 0) return na_container();
        if (id === 'na-section-window-board') return na_windowBoardSection;
        return null;
    },
    querySelector    : (selector) => {
        const match = /\[data-control-id="([^"]+)"\]/.exec(String(selector));
        if (!match) return null;
        if (!na_controls[match[1]]) na_controls[match[1]] = na_stubElement('');
        return na_controls[match[1]];
    },
    querySelectorAll : () => [],
    addEventListener : () => {},
    createElementNS  : () => ({ setAttribute: () => {}, appendChild: () => {} })
};
window.Na__Ui__Controls = { na_createControl: () => '' };
const na_console_error  = console.error;
console.error           = (message, ...rest) => {               // <-- No viewport is built here; keep every other error
    if (String(message).indexOf('[NA_VIEWPORT]') === 0) return;
    na_console_error(message, ...rest);
};
window.Na__Ui__Events   = { na_attachEventListeners: (config, callback) => { na_onControlChange = callback; } };

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Load the Shipped Modules
// -----------------------------------------------------------------------------

const NA_SOURCES = [
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__Config__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__MullionMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__MainUiLogic__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Bridge__.js'
];

// Each shipped file declares top-level `const`s, which would collide across a
// shared eval scope, so every source is evaluated in its own function scope.
const na_console_log = console.log;
console.log = () => {};                                                // <-- Silence the dialog's own init logging
NA_SOURCES.forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + na_read(relativePath) + '\n})()');
});

const Ui  = window.Na_DynamicUI;
const Svg = window.Na__Viewport__SvgGenerator;
Ui.na_init();
console.log = na_console_log;

// HELPER FUNCTION | Change One Control the Way a Click Does
// ------------------------------------------------------------
function na_set(id, value) {
    na_onControlChange(id, value);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Read One Key From the Live Config
// ------------------------------------------------------------
function na_get(id) {
    return Ui.na_getConfig()[id];
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Display of the Window Board Section and Its Toggle
// ------------------------------------------------------------
function na_sectionShown() {
    return na_windowBoardSection.style.display !== 'none';
}

function na_toggleShown() {
    return !na_controls.window_board_enabled || na_controls.window_board_enabled.style.display !== 'none';
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Defaults, and Parity With the Ruby Defaults
// -----------------------------------------------------------------------------

na_suite('Defaults');
na_expect('Real control-change handler captured', typeof na_onControlChange, 'function');
na_expect('Window board starts off', na_get('window_board_enabled'), false);
na_expect('Reveal Depth defaults to 250mm', na_get('window_board_reveal_depth_mm'), 250);
na_expect('Nosing Overhang defaults to 30mm', na_get('window_board_nosing_overhang_mm'), 30);
na_expect('Nosing Type defaults to Type 01', na_get('window_board_nosing_type'), '1');
na_expect('Nosing returns past the reveal by default', na_get('window_board_nosing_returns_enabled'), true);
na_expect('Window board edges default to Medium Dark Grey', na_get('edge_colour_window_board_id'), 'MTE103__LineColour__MediumDarkGrey__L50');

const NA_RUBY_DEFAULTS_SRC = na_read('20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Defaults__.rb');
const NA_RUBY_DEFAULTS = JSON.parse(
    NA_RUBY_DEFAULTS_SRC.split('NA_DEFAULT_CONFIG_JSON = <<~JSON_STRING')[1].split('JSON_STRING')[0]
).windowConfiguration;
[
    'window_board_enabled',
    'window_board_reveal_depth_mm',
    'window_board_nosing_overhang_mm',
    'window_board_nosing_type',
    'window_board_nosing_returns_enabled',
    'edge_colour_window_board_id'
].forEach((key) => {
    na_expect('Ruby default matches the dialog: ' + key, NA_RUBY_DEFAULTS[key], na_get(key));
});

const NA_APP_CONFIG = JSON.parse(na_read('02__AppData/Na__AssemblyStudio__AppConfig__Main.json')).appConfig;
na_expect('AppConfig names the window board asset bucket', NA_APP_CONFIG.assetLibrary.window.windowBoards, 'Windows__WindowBoards__');

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Include Window Board Shows the Section, Windows Only
// -----------------------------------------------------------------------------

na_suite('Include Window Board opens the WINDOW BOARD section');
na_expect('Section hidden while the board is off', na_sectionShown(), false);
na_expect('Toggle shown on a casement window', na_toggleShown(), true);

na_set('window_board_enabled', true);
na_expect('Toggle on shows the section', na_sectionShown(), true);

na_set('ui_window_type', 'SlidingSash');
na_expect('Section stays on a sliding sash window', na_sectionShown(), true);
na_set('ui_window_type', 'Casement');

na_set('ui_element_category', 'ExteriorDoors');
na_expect('Exterior doors hide the section', na_sectionShown(), false);
na_expect('Exterior doors hide the toggle', na_toggleShown(), false);
['Single', 'Sliding', 'MultiFold', 'Double'].forEach((doorType) => {
    na_set('ui_exterior_door_type', doorType);
    na_expect('Section hidden on ' + doorType, na_sectionShown(), false);
});

na_set('ui_element_category', 'Window');
na_expect('Back on windows the section returns', na_sectionShown(), true);
na_expect('Back on windows the toggle returns', na_toggleShown(), true);
na_expect('The board setting survived the door detour', na_get('window_board_enabled'), true);

na_set('window_board_enabled', false);
na_expect('Toggle off hides the section', na_sectionShown(), false);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Loading Saved Windows
// -----------------------------------------------------------------------------

na_suite('A selected window loads with its own board, or none');

// A saved window that has a board: every value comes back as saved.
window.na_setInitialConfig(JSON.stringify({
    windowConfiguration: {
        window_board_enabled                : true,
        window_board_reveal_depth_mm        : 320,
        window_board_nosing_overhang_mm     : 42,
        window_board_nosing_type            : '2',
        window_board_nosing_returns_enabled : false
    }
}));
na_expect('Saved board switched on', na_get('window_board_enabled'), true);
na_expect('Saved reveal depth kept', na_get('window_board_reveal_depth_mm'), 320);
na_expect('Saved overhang kept', na_get('window_board_nosing_overhang_mm'), 42);
na_expect('Saved nosing type kept', na_get('window_board_nosing_type'), '2');
na_expect('Saved square ends kept', na_get('window_board_nosing_returns_enabled'), false);
na_expect('Section open for a window with a board', na_sectionShown(), true);

// A window saved before V1.9.0 has no window board keys at all. It must not
// inherit the board the previous window had.
window.na_setInitialConfig(JSON.stringify({ windowConfiguration: { width_mm: 1200, height_mm: 1100 } }));
na_expect('Pre-V1.9.0 window loads with the board off', na_get('window_board_enabled'), false);
na_expect('Pre-V1.9.0 window hides the section', na_sectionShown(), false);

// A measured opening updates only width and height and must leave the board alone.
na_set('window_board_enabled', true);
Ui.na_setConfig({ width_mm: 1500, height_mm: 1350 });
na_expect('Measuring an opening keeps the board on', na_get('window_board_enabled'), true);
na_set('window_board_enabled', false);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | 2D Preview Outline
// -----------------------------------------------------------------------------

na_suite('The preview draws the board under the frame');

// HELPER FUNCTION | Read the Board Outline Rect From Generated SVG
// ------------------------------------------------------------
function na_outline(config) {
    const markup = Svg.na_generateWindowSvg(Object.assign({ width_mm: 900, height_mm: 1200 }, config));
    const match  = /<rect class="na-window-board-outline" x="([^"]+)" y="([^"]+)" width="([^"]+)" height="([^"]+)"/.exec(markup);
    return match ? { x: Number(match[1]), y: Number(match[2]), width: Number(match[3]), height: Number(match[4]) } : null;
}
// ---------------------------------------------------------------

na_expect('No outline while the board is off', na_outline({ window_board_enabled: false }), null);
na_expect('Returned nosing: one thickness past each side',
          na_outline({ window_board_enabled: true }), { x: -30, y: 0, width: 960, height: 30 });
na_expect('Square ends: flush with the reveal',
          na_outline({ window_board_enabled: true, window_board_nosing_returns_enabled: false }), { x: 0, y: 0, width: 900, height: 30 });
na_expect('Hinged doors never draw a board',
          na_outline({ window_board_enabled: true, double_door_mode: true }), null);

window.NA_WINDOW_BOARD_ASSET_CACHE = {
    '3': { Na__Asset__Profile2D: { Na__Geometry__Vertices: [{ PosZ_mm: 0 }, { PosZ_mm: 25 }, { PosZ_mm: 25 }, { PosZ_mm: 0 }] } }
};
na_expect('Thickness read off the nosing profile',
          na_outline({ window_board_enabled: true, window_board_nosing_type: '3' }), { x: -25, y: 0, width: 950, height: 25 });
na_expect('A type missing from the cache falls back to 30mm', Svg.na_getWindowBoardThickness('1'), 30);
delete window.NA_WINDOW_BOARD_ASSET_CACHE;

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Nosing Assets
// -----------------------------------------------------------------------------

na_suite('Nosing assets');

// HELPER FUNCTION | Ordered Outer Loop [[y, z], ...] of a Profile2D Asset
// ------------------------------------------------------------
function na_loop(asset) {
    const profile = asset.Na__Asset__Profile2D;
    const table   = {};
    profile.Na__Geometry__Vertices.forEach((v) => { table[v.VertexId] = [v.PosY_mm, v.PosZ_mm]; });
    const face = profile.Na__Geometry__Faces[0];
    return (face.OuterLoop_VertexIds || face.OuterLoopVertices).map((id) => table[id]);
}

// HELPER FUNCTION | Nose Points (In Front of the Wall Face Line), Sorted
// ------------------------------------------------------------
function na_nose(loop) {
    return loop.filter((p) => p[0] < -0.001).map((p) => p.join(',')).sort();
}

// HELPER FUNCTION | Signed Area of a Loop (Negative = Clockwise)
// ------------------------------------------------------------
function na_signedArea(loop) {
    let sum = 0;
    loop.forEach((p, i) => {
        const q = loop[(i + 1) % loop.length];
        sum += (p[0] * q[1]) - (q[0] * p[1]);
    });
    return sum / 2;
}
// ---------------------------------------------------------------

const NA_TYPE_OPTIONS = window.NA_WINDOW_BOARD_CONFIG
    .find((d) => d.id === 'window_board_nosing_type').options.map((o) => o.value);
const NA_FILES = fs.readdirSync(NA_BOARDS).filter((name) => /^Na__Window__WindowBoard__Type-\d\d__.*__\.json$/.test(name)).sort();
na_expect('One asset per Nosing Type option', NA_FILES.length, NA_TYPE_OPTIONS.length);

const NA_ASSETS = {};
NA_FILES.forEach((name) => {
    const asset  = JSON.parse(fs.readFileSync(path.join(NA_BOARDS, name), 'utf8'));
    const typeId = String(Number(/Type-(\d\d)/.exec(name)[1]));
    NA_ASSETS[typeId] = asset;
    const params = asset.Na__WindowBoard__Parameters;
    const loop   = na_loop(asset);
    const zs     = loop.map((p) => p[1]);

    na_expect(name + ': type id matches the file name', params.Na__WindowBoard__NosingTypeId, typeId);
    na_expect(name + ': offered in the Nosing Type list', NA_TYPE_OPTIONS.indexOf(typeId) >= 0, true);
    na_expect(name + ': meta.fileName is the file', asset.meta.fileName, name);
    na_expect(name + ': a 2D profile asset', asset.Na__Asset__Metadata.Na__Asset__Has2dProfile, true);
    na_expect(name + ': 30mm thick', Math.max(...zs) - Math.min(...zs), 30);
    na_expect(name + ': declared thickness agrees', params.Na__WindowBoard__Thickness_mm, 30);
    na_expect(name + ': nose tip 30mm proud of the wall face', Math.min(...loop.map((p) => p[0])), -30);
    na_expect(name + ': drawn at the 250mm standard reveal', Math.max(...loop.map((p) => p[0])), 250);
    na_expect(name + ': loop runs clockwise', na_signedArea(loop) < 0, true);
    na_expect(name + ': Medium Dark Grey edges',
              asset.Na__Asset__Profile2D.Na__Geometry__Edges.every((e) => e.EdgeColourId === 'MTE103__LineColour__MediumDarkGrey__L50'), true);
});

na_expect('Type 01 nose is 12.5mm deep', NA_ASSETS['1'].Na__WindowBoard__Parameters.Na__WindowBoard__NoseDepth_mm, 12.5);
na_expect('Type 02 is a full bullnose: no step, nose 15mm deep',
          NA_ASSETS['2'].Na__WindowBoard__Parameters.Na__WindowBoard__NoseDepth_mm, 15);
na_expect('Nosing Overhang slider starts clear of every nose',
          window.NA_WINDOW_BOARD_CONFIG.find((d) => d.id === 'window_board_nosing_overhang_mm').min >
          Math.max(...Object.keys(NA_ASSETS).map((k) => NA_ASSETS[k].Na__WindowBoard__Parameters.Na__WindowBoard__NoseDepth_mm)), true);
na_expect('Type 03 is square: four corners only', na_loop(NA_ASSETS['3']).length, 4);

if (fs.existsSync(NA_PPT_PRF90021)) {
    const ppt = JSON.parse(fs.readFileSync(NA_PPT_PRF90021, 'utf8'));
    na_expect('Type 01 keeps the PRF90021 nose exactly', na_nose(na_loop(NA_ASSETS['1'])), na_nose(na_loop(ppt)));
} else {
    console.log('  (skipped: PRF90021 not found beside this plugin)');
}

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
