/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - DOOR TYPE SWITCH SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__DoorTypeSwitch__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for the V1.7.2 Door Type switch - flicking
                between Double Doors, Single Door, Sliding Doors and
                MultiFolding Door carries every shared setting across, and
                only width and height reset to the new type's defaults.
   CREATED    : 21-Oct-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__DoorTypeSwitch__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHY THIS EXISTS:
   Each door type keeps its leaf settings under its own key prefix
   (double_door_*, single_door_*, sliding_door_*, bifold_door_*), so a switch
   used to land on the new type's untouched defaults. Nothing threw - the
   stiles, rails, fielded panels, handles and finish simply went back to
   factory values every time.

   The suite loads the SHIPPED control configs and the WindowSystem
   MainUiLogic unmodified against an empty DOM stub, captures the real
   control-change handler the Events module would bind, and drives the Door
   Type control through it exactly as a click does.

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

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Empty DOM Stub
// -----------------------------------------------------------------------------

// Every control lookup misses, so the UI logic updates only its config - the
// state under test. The control containers exist so na_buildControls reaches
// the Events module, which is where the real change handler is captured.
let na_onControlChange = null;

function na_container() {
    return { innerHTML: '', insertAdjacentHTML: () => {} };
}

global.window   = global;
global.document = {
    getElementById   : (id) => (String(id).indexOf('na-controls-') === 0 ? na_container() : null),
    querySelector    : () => null,
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
    '20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__MainUiLogic__.js'
];

// Each shipped file declares top-level `const`s, which would collide across a
// shared eval scope, so every source is evaluated in its own function scope.
const na_console_log = console.log;
console.log = () => {};                                                // <-- Silence the dialog's own init logging
NA_SOURCES.forEach((relativePath) => {
    // eslint-disable-next-line no-eval
    (0, eval)('(function(){' + na_read(relativePath) + '\n})()');
});

const Ui = window.Na_DynamicUI;
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

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Fixture - A Customised Pair of Doors
// -----------------------------------------------------------------------------

na_suite('Harness');
na_expect('Real control-change handler captured', typeof na_onControlChange, 'function');

na_set('ui_element_category', 'ExteriorDoors');
na_set('ui_exterior_door_type', 'Double');
na_expect('Entering Exterior Doors lands on Double Doors', na_get('double_door_mode'), true);

// Every value differs from both its own default and the single door's
// default, so a carried value can never pass by coincidence.
const NA_DOUBLE_SETUP = {
    double_door_leaf_composition            : 'FullyFielded',
    double_door_leaf_thickness_mm           : 58,
    double_door_panel_stile_width_mm        : 115,
    double_door_panel_top_rail_width_mm     : 110,
    double_door_panel_bottom_rail_width_mm  : 210,
    double_door_mid_rail_width_mm           : 140,
    double_door_panel_output_mode           : 'Linework',
    double_door_panel_profile               : 'RecessedShaker',
    double_door_panel_preset                : 'Custom',
    double_door_panel_columns               : 2,
    double_door_panel_rows                  : 3,
    double_door_fielded_section_height_mm   : 650,
    double_door_panel_inset_mm              : 40,
    double_door_panel_depth_mm              : 16,
    double_door_panel_bevel_width_mm        : 30,
    double_door_fixed_panels                : true,
    double_door_swing_direction             : 'Outward',
    double_door_show_swing_arcs             : false,
    double_door_create_open_state_copy      : false,
    double_door_handle_asset_key            : 'Na__ExteriorDoor__Handle__Test',
    double_door_handle_height_mm            : 1050,
    double_door_handle_backset_mm           : 70,
    double_door_leaf_material_id            : 'MAT999__Test__Paint',
    double_door_handle_material_id          : 'MAT998__Test__Brass'
};
Object.keys(NA_DOUBLE_SETUP).forEach((key) => na_set(key, NA_DOUBLE_SETUP[key]));

// Settings every product already shares under one unprefixed key.
na_set('fuse_parts', false);
na_set('frame_depth_mm', 95);
na_set('frame_wall_inset_mm', 35);
na_set('horizontal_glaze_bars', 2);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Double -> Single
// -----------------------------------------------------------------------------

na_suite('Double Doors -> Single Door');

na_set('width_mm', 2400);
na_set('height_mm', 2300);
na_set('ui_exterior_door_type', 'Single');

na_expect('Single door mode is active', na_get('ext_single_door_mode'), true);
Object.keys(NA_DOUBLE_SETUP).forEach((key) => {
    const singleKey = key.replace('double_door_', 'single_door_');
    na_expect(singleKey + ' carried from the pair', na_get(singleKey), NA_DOUBLE_SETUP[key]);
});
na_expect('Width resets to the single door default', na_get('width_mm'), 1000);
na_expect('Height resets to the door default', na_get('height_mm'), 2100);
na_expect('fuse_parts survives', na_get('fuse_parts'), false);
na_expect('frame_depth_mm survives', na_get('frame_depth_mm'), 95);
na_expect('frame_wall_inset_mm survives', na_get('frame_wall_inset_mm'), 35);
na_expect('horizontal_glaze_bars survives', na_get('horizontal_glaze_bars'), 2);
na_expect('Swing side is the single door\'s own (no pair equivalent)', na_get('single_door_swing_side'), 'Left');

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Single -> Double
// -----------------------------------------------------------------------------

na_suite('Single Door -> Double Doors (an edit made on the single comes back)');

na_set('single_door_panel_stile_width_mm', 125);
na_set('single_door_handle_height_mm', 980);
na_set('single_door_opening_angle_deg', 60);
na_set('single_door_hinge_projection_mm', 15);
na_set('ui_exterior_door_type', 'Double');

na_expect('Double door mode is active', na_get('double_door_mode'), true);
na_expect('Stile edit carried back', na_get('double_door_panel_stile_width_mm'), 125);
na_expect('Handle height edit carried back', na_get('double_door_handle_height_mm'), 980);
na_expect('Composition still carried', na_get('double_door_leaf_composition'), 'FullyFielded');
na_expect('Leaf finish still carried', na_get('double_door_leaf_material_id'), 'MAT999__Test__Paint');
na_expect('Opening angle goes to the left leaf', na_get('double_door_left_opening_angle_deg'), 60);
na_expect('Opening angle goes to the right leaf', na_get('double_door_right_opening_angle_deg'), 60);
na_expect('Hinge projection goes to the left leaf', na_get('double_door_left_hinge_projection_mm'), 15);
na_expect('Hinge projection goes to the right leaf', na_get('double_door_right_hinge_projection_mm'), 15);
na_expect('Width resets to the double door default', na_get('width_mm'), 1800);
na_expect('Active leaf width re-seeds to EQ', na_get('double_door_active_leaf_width_mm'), 'EQ');

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Per-Leaf Values Follow the Active Leaf
// -----------------------------------------------------------------------------

na_suite('Double Doors -> Single Door reads the active leaf');

na_set('double_door_active_leaf', 'Right');
na_set('double_door_left_opening_angle_deg', 0);
na_set('double_door_right_opening_angle_deg', 120);
na_set('ui_exterior_door_type', 'Single');
na_expect('Single takes the open (active) leaf\'s angle', na_get('single_door_opening_angle_deg'), 120);

na_set('ui_exterior_door_type', 'Double');
na_set('double_door_active_leaf', 'Left');
na_set('double_door_left_opening_angle_deg', 45);
na_set('double_door_right_opening_angle_deg', 0);
na_set('ui_exterior_door_type', 'Single');
na_expect('Left active leaf supplies the angle', na_get('single_door_opening_angle_deg'), 45);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Hinged -> Sliding / MultiFold
// -----------------------------------------------------------------------------

na_suite('Single Door -> Sliding Doors (renamed rails map across)');

const NA_SINGLE_BEFORE_SLIDING = {
    single_door_leaf_material_id : na_get('single_door_leaf_material_id'),
    single_door_handle_height_mm : na_get('single_door_handle_height_mm')
};
na_set('ui_exterior_door_type', 'Sliding');

na_expect('Sliding mode is active', na_get('sliding_mode'), true);
na_expect('Stile -> sliding_door_stile_width_mm', na_get('sliding_door_stile_width_mm'), 125);
na_expect('Top rail -> sliding_door_head_rail_mm', na_get('sliding_door_head_rail_mm'), 110);
na_expect('Bottom rail -> sliding_door_base_rail_mm', na_get('sliding_door_base_rail_mm'), 210);
na_expect('Leaf thickness -> sliding_door_panel_thickness_mm', na_get('sliding_door_panel_thickness_mm'), 58);
na_expect('Composition carried', na_get('sliding_door_leaf_composition'), 'FullyFielded');
na_expect('Panel profile carried', na_get('sliding_door_panel_profile'), 'RecessedShaker');
na_expect('Panel inset carried', na_get('sliding_door_panel_inset_mm'), 40);
na_expect('Width resets to the sliding default', na_get('width_mm'), 3000);
na_expect('Sliding-only rear setback untouched', na_get('sliding_door_rear_setback_mm'),
    window.NA_SLIDING_DOOR_CONFIG.find((item) => item.id === 'sliding_door_rear_setback_mm').default);

na_suite('Sliding Doors -> MultiFolding Door');

na_set('sliding_door_leaf_composition', 'FullyGlazed');
na_set('sliding_door_base_rail_mm', 230);
na_set('ui_exterior_door_type', 'MultiFold');

na_expect('MultiFold mode is active', na_get('multifold_mode'), true);
na_expect('Base rail carried', na_get('bifold_door_base_rail_mm'), 230);
na_expect('Stile carried', na_get('bifold_door_stile_width_mm'), 125);
na_expect('Composition carried', na_get('bifold_door_leaf_composition'), 'FullyGlazed');
na_expect('Legacy bifold_door_glazed follows the carried composition', na_get('bifold_door_glazed'), true);

na_suite('MultiFolding Door -> Single Door (hinged-only settings kept)');

na_set('ui_exterior_door_type', 'Single');
na_expect('Base rail carried back to the hinged key', na_get('single_door_panel_bottom_rail_width_mm'), 230);
na_expect('Composition carried back', na_get('single_door_leaf_composition'), 'FullyGlazed');
na_expect('Leaf finish kept (multifold has none)', na_get('single_door_leaf_material_id'),
    NA_SINGLE_BEFORE_SLIDING.single_door_leaf_material_id);
na_expect('Handle height kept (multifold has none)', na_get('single_door_handle_height_mm'),
    NA_SINGLE_BEFORE_SLIDING.single_door_handle_height_mm);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Window Round Trip and Loaded Doors
// -----------------------------------------------------------------------------

na_suite('Windows <-> Exterior Doors does not transpose');

na_set('single_door_panel_inset_mm', 22);
na_set('ui_element_category', 'Window');
na_set('ui_element_category', 'ExteriorDoors');
na_expect('Back on the single door', na_get('ext_single_door_mode'), true);
na_expect('Single door settings untouched by the round trip', na_get('single_door_panel_inset_mm'), 22);

na_suite('A door loaded from SketchUp keeps what it was saved with');

Ui.na_setConfig({
    double_door_mode                  : true,
    ext_single_door_mode              : false,
    double_door_panel_stile_width_mm  : 80,
    single_door_panel_stile_width_mm  : 140,
    width_mm                          : 2250
});
na_expect('Loaded pair keeps its stile', na_get('double_door_panel_stile_width_mm'), 80);
na_expect('Loaded config leaves the single door key alone', na_get('single_door_panel_stile_width_mm'), 140);
na_expect('Loaded width kept', na_get('width_mm'), 2250);

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
