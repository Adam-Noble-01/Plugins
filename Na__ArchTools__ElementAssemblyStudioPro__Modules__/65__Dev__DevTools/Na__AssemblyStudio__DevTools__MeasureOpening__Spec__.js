/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - MEASURE OPENING KEEPS YOUR SETTINGS SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__MeasureOpening__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for the V1.9.1 fix - a measured opening
                changes the window's width and height and nothing else.
   CREATED    : 26-Oct-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__MeasureOpening__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHY THIS EXISTS
   Measure Opening hands the dialog just the width and height, through
   window.na_receiveMeasurement -> Na_DynamicUI.na_setConfig. Until V1.9.1
   na_setConfig ran the pre-V1.9.5 Glaze Bar Offsets hydration on whatever
   it was given; a two-key update holds no nudge keys, so it read as an old
   window with no nudges and switched Glaze Bar Offsets off every time.

   The suite loads the SHIPPED window modules and the SHIPPED bridge against
   an empty DOM stub, and calls the two real Ruby -> JS entry points:
   window.na_receiveMeasurement (a measured opening) and
   window.na_setInitialConfig (a window selected in SketchUp, which must
   still hydrate keys an older window does not hold).

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

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | DOM Stub and Shipped Modules
// -----------------------------------------------------------------------------

// Every element lookup misses (the bridge and UI logic guard each one), so
// only the configuration under test changes.
let na_onControlChange = null;

global.window   = global;
global.document = {
    getElementById   : (id) => (String(id).indexOf('na-controls-') === 0
        ? { innerHTML: '', insertAdjacentHTML: () => {} }
        : null),
    querySelector    : () => null,
    querySelectorAll : () => [],
    addEventListener : () => {},
    createElementNS  : () => ({ setAttribute: () => {}, appendChild: () => {} }),
    createElement    : () => ({ appendChild: () => {} })
};
window.Na__Ui__Controls = { na_createControl: () => '' };
window.Na__Ui__Events   = { na_attachEventListeners: (config, callback) => { na_onControlChange = callback; } };
const na_console_error  = console.error;
console.error = (message, ...rest) => {                              // <-- No viewport is built here; keep every other error
    if (String(message).indexOf('[NA_VIEWPORT]') === 0) return;
    na_console_error(message, ...rest);
};

const NA_SOURCES = [
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Config__.js',
    '31__System__ExteriorSingleDoorSystem/Na__AssemblyStudio__ExtSingleDoor__UiSystem__Config__.js',
    '32__System__ExteriorSlidingDoorSystem/Na__AssemblyStudio__ExtSlide__UiSystem__Config__.js',
    '33__System__ExteriorMultiFoldingDoorSystem/Na__AssemblyStudio__ExtFold__UiSystem__Config__.js',
    '34__System__ExteriorDoubleDoorSystem/Na__AssemblyStudio__ExtDouble__UiSystem__Config__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__MullionMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__CasementMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js',
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__Viewport__SvgGenerator__.js',
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
Ui.na_init();
console.log = (message, ...rest) => {                                // <-- Keep the suite's output, drop the dialog's own [NA_*] logging
    if (String(message).indexOf('[NA_') === 0) return;
    na_console_log(message, ...rest);
};

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

// HELPER FUNCTION | Select a Window the Way Ruby Pushes It
// ------------------------------------------------------------
function na_selectWindow(windowConfiguration) {
    window.na_setInitialConfig(JSON.stringify({
        windowMetadata      : [{ WindowUniqueId: 'AWN042', WindowName: 'Saved window' }],
        windowComponents    : [],
        windowConfiguration : windowConfiguration
    }));
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | A Measured Opening Changes Width and Height Only
// -----------------------------------------------------------------------------

na_suite('Harness');
na_expect('Real control-change handler captured', typeof na_onControlChange, 'function');
na_expect('Real measurement entry point loaded', typeof window.na_receiveMeasurement, 'function');

na_suite('Measure Opening keeps Glaze Bar Offsets');

na_set('horizontal_glaze_bars', 2);
na_set('glazebar_offsets_enabled', true);
na_set('glazebar_h_offset_1_mm', 40);
window.na_receiveMeasurement(1500, 1100);
na_expect('Width is the measured width', na_get('width_mm'), 1500);
na_expect('Height is the measured height', na_get('height_mm'), 1100);
na_expect('Glaze Bar Offsets stays on', na_get('glazebar_offsets_enabled'), true);
na_expect('The nudge is kept', na_get('glazebar_h_offset_1_mm'), 40);

na_set('glazebar_offsets_enabled', false);
window.na_receiveMeasurement(1600, 1000);
na_expect('An Off toggle stays off too', na_get('glazebar_offsets_enabled'), false);

na_suite('Measure Opening keeps everything else');

na_set('mullions', 2);
na_set('leaded_global_alignment', false);
na_set('advanced_frame_controls', true);
na_set('frame_left_thickness_mm', 80);
Ui.na_setConfig({ casement_overrides: { '1:0:0': { enabled: true, top_rail_mm: 100 } } });
na_set('glazebar_offsets_enabled', true);                            // <-- Last, so nothing before the snapshot can have reset it
const NA_SNAPSHOT = Ui.na_getConfig();
window.na_receiveMeasurement(1800, 1200);
const NA_AFTER = Ui.na_getConfig();
const NA_CHANGED = Object.keys(NA_AFTER)
    .filter(key => JSON.stringify(NA_AFTER[key]) !== JSON.stringify(NA_SNAPSHOT[key]))
    .sort();
na_expect('Only width and height change', NA_CHANGED, ['height_mm', 'width_mm']);
na_expect('Per Casement Settings kept', NA_AFTER.casement_overrides, { '1:0:0': { enabled: true, top_rail_mm: 100 } });
na_expect('Align Lead Lines setting kept', NA_AFTER.leaded_global_alignment, false);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | A Selected Window Still Hydrates What It Does Not Hold
// -----------------------------------------------------------------------------

na_suite('Selecting a saved window');

const NA_WINDOW = {
    width_mm: 900, height_mm: 1200, mullions: 0, horizontal_glaze_bars: 2, vertical_glaze_bars: 0,
    removed_casements: [], removed_transom_segments: [], removed_glazebars: [], leaded_disabled_cells: []
};

na_selectWindow(Object.assign({}, NA_WINDOW, { glazebar_h_offset_1_mm: 30 }));
na_expect('A pre-V1.9.5 window with nudges gets Glaze Bar Offsets on', na_get('glazebar_offsets_enabled'), true);

na_selectWindow(Object.assign({}, NA_WINDOW, { glazebar_h_offset_1_mm: 0, glazebar_h_offset_2_mm: 0 }));
na_expect('A pre-V1.9.5 window without nudges gets it off', na_get('glazebar_offsets_enabled'), false);

na_selectWindow(Object.assign({}, NA_WINDOW, { glazebar_offsets_enabled: false, glazebar_h_offset_1_mm: 30 }));
na_expect('A saved Off is respected', na_get('glazebar_offsets_enabled'), false);

na_selectWindow(Object.assign({}, NA_WINDOW));
na_expect('A pre-V1.8.0 window starts with no casement overrides', na_get('casement_overrides'), {});
na_expect('A pre-V1.8.0 window keeps pane-by-pane lead', na_get('leaded_global_alignment'), false);

window.na_receiveMeasurement(1200, 1400);
na_expect('Measuring that window afterwards still only sizes it', [na_get('width_mm'), na_get('height_mm'), na_get('glazebar_offsets_enabled')], [1200, 1400, false]);

// endregion -------------------------------------------------------------------


console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);
