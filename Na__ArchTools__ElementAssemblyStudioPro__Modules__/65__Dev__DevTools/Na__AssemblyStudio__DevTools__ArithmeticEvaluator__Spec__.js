/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - ARITHMETIC ENTRY SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__ArithmeticEvaluator__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for the numeric-field calculator - the shared
                evaluator, the shared slider/EQ wiring, and the Interior Door
                tab's own copy of the helpers.
   CREATED    : 27-Aug-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__ArithmeticEvaluator__Spec__.js"

   Exits 0 when everything passes, 1 on the first failing assertion set, so it
   drops straight into a pre-commit hook if that is ever wanted.

   WHY THIS EXISTS:
   The evaluator is pure logic with no SketchUp dependency, and it now sits
   under every dimension the tool can produce. A parser that silently returns
   the wrong number is far more damaging than one that throws, so the grammar,
   the clamping and the failure paths are pinned down here rather than being
   re-checked by hand in the dialog.

   The suites load the SHIPPED source files unmodified - a minimal DOM stub
   stands in for the browser - so this tests what actually runs.

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
// REGION | Minimal DOM Stub
// -----------------------------------------------------------------------------
// Just enough of an element to drive the real event wiring: attributes that
// reflect like the browser's, a working classList, and manual event firing.

const na_registry = {};

// HELPER FUNCTION | Create and Register a Fake Element
// ------------------------------------------------------------
function na_make_element(id) {
    const classes = new Set();
    const element = {
        id            : id,
        value         : '',
        textContent   : '',
        attrs         : {},
        dataset       : {},
        listeners     : {},
        classList     : {
            add     : (name) => classes.add(name),
            remove  : (name) => classes.delete(name),
            contains: (name) => classes.has(name),
            toggle  : (name, on) => (on ? classes.add(name) : classes.delete(name))
        },
        getAttribute    : (name) => (element.attrs[name] === undefined ? null : String(element.attrs[name])),
        setAttribute    : (name, value) => { element.attrs[name] = value; },
        addEventListener: (name, handler) => {
            element.listeners[name] = element.listeners[name] || [];
            element.listeners[name].push(handler);
        },
        removeEventListener: () => {},
        fire            : (name, event) => (element.listeners[name] || [])
                            .forEach((handler) => handler(event || { preventDefault: () => {} }))
    };
    ['min', 'max', 'step'].forEach((property) => Object.defineProperty(element, property, {
        get: () => element.attrs[property],
        set: (value) => { element.attrs[property] = value; }
    }));
    na_registry[id] = element;
    return element;
}
// ---------------------------------------------------------------

global.window   = {};
global.document = {
    getElementById: (id) => na_registry[id] || null,
    querySelector : () => null
};

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Load the Shipped Sources
// -----------------------------------------------------------------------------

function na_read(relativePath) {
    return fs.readFileSync(path.join(NA_MODULES, relativePath), 'utf8');
}

const NA_QUIET = console.log;
console.log = () => {};                                                         // <-- Silence module load banners
eval(na_read('03__AppUtils/Na__AssemblyStudio__AppUtils__ArithmeticEvaluator__.js'));
eval(na_read('01__AppCore/Na__AssemblyStudio__AppCore__UiSystem__Events__.js'));
console.log = NA_QUIET;

const Arithmetic = global.window.Na__Utils__Arithmetic;
const Events     = global.window.Na__Ui__Events;

// The Interior Door tab keeps its own copy of these helpers because it builds
// sliders imperatively rather than through Na__Ui__Controls. Its arithmetic
// region is lifted out of the shipped file so the real code is exercised here
// too, rather than a paraphrase of it drifting out of sync.
const na_door_source = na_read('40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__UiSystem__MainUiLogic__.js');
const na_region_start = na_door_source.indexOf('// REGION | Arithmetic Entry Helpers');
const na_region_end   = na_door_source.indexOf('// REGION | Control HTML Builders');
if (na_region_start < 0 || na_region_end < 0) {
    console.log('FATAL: could not locate the Interior Door arithmetic helper region.');
    console.log('       The REGION banners in the Interior Door MainUiLogic have moved.');
    process.exit(1);
}
const InteriorDoor = {};
eval(na_door_source.slice(na_region_start, na_region_end) + `
    InteriorDoor.na_format_number        = na_format_number;
    InteriorDoor.na_is_plain_number_text = na_is_plain_number_text;
    InteriorDoor.na_starts_with_operator = na_starts_with_operator;
    InteriorDoor.na_resolve_typed_value  = na_resolve_typed_value;
    InteriorDoor.na_resolve_step_key     = na_resolve_step_key;
`);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite - Grammar
// -----------------------------------------------------------------------------

na_suite('Grammar');
na_expect('subtract',              Arithmetic.na_evaluate('1700-50').value, 1650);
na_expect('add',                   Arithmetic.na_evaluate('2400+200').value, 2600);
na_expect('divide',                Arithmetic.na_evaluate('2400/3').value, 800);
na_expect('multiply',              Arithmetic.na_evaluate('800*3').value, 2400);
na_expect('bracketed sum',         Arithmetic.na_evaluate('2400+(100+100+100+100)').value, 2800);
na_expect('nested brackets',       Arithmetic.na_evaluate('((100+50)*2)-100').value, 200);
na_expect('three equal lights',    Arithmetic.na_evaluate('(3000-2*95)/3').value, 936.667);
na_expect('precedence',            Arithmetic.na_evaluate('100+50*2').value, 200);
na_expect('spaces ignored',        Arithmetic.na_evaluate(' 1700 - 50 ').value, 1650);
na_expect('unary minus',           Arithmetic.na_evaluate('-50+100').value, 50);
na_expect('double unary',          Arithmetic.na_evaluate('100--50').value, 150);
na_expect('decimals',              Arithmetic.na_evaluate('1650.5+0.5').value, 1651);
na_expect('leading dot',           Arithmetic.na_evaluate('.5+.5').value, 1);
na_expect('power',                 Arithmetic.na_evaluate('2^3').value, 8);
na_expect('power right assoc',     Arithmetic.na_evaluate('2^3^2').value, 512);
na_expect('negated power',         Arithmetic.na_evaluate('-2^2').value, -4);
na_expect('unicode multiply',      Arithmetic.na_evaluate('3×600').value, 1800);
na_expect('unicode divide',        Arithmetic.na_evaluate('2400÷3').value, 800);
na_expect('unicode minus',         Arithmetic.na_evaluate('1700−50').value, 1650);
na_expect('x means multiply',      Arithmetic.na_evaluate('3x600').value, 1800);
na_expect('thousands separator',   Arithmetic.na_evaluate('1,700-50').value, 1650);
na_expect('float noise removed',   Arithmetic.na_evaluate('0.1+0.2').value, 0.3);
na_expect('recurring rounded',     Arithmetic.na_evaluate('2400/7').value, 342.857);


// -----------------------------------------------------------------------------
// REGION | Suite - Rejected Entries
// -----------------------------------------------------------------------------
// Every one of these must fail cleanly. Silently resolving to something is far
// worse than refusing, because the result becomes a manufactured dimension.

na_suite('Rejected entries');
na_expect('empty',                 Arithmetic.na_evaluate('').ok, false);
na_expect('trailing operator',     Arithmetic.na_evaluate('1700-').ok, false);
na_expect('lone operator',         Arithmetic.na_evaluate('*').ok, false);
na_expect('unclosed bracket',      Arithmetic.na_evaluate('(100+50').ok, false);
na_expect('unmatched close',       Arithmetic.na_evaluate('100+50)').ok, false);
na_expect('divide by zero',        Arithmetic.na_evaluate('100/0').ok, false);
na_expect('letters',               Arithmetic.na_evaluate('abc').ok, false);
na_expect('doubled operator',      Arithmetic.na_evaluate('100**50').ok, false);
na_expect('two numbers no operator', Arithmetic.na_evaluate('100 50').ok, false);
na_expect('bare dot',              Arithmetic.na_evaluate('.').ok, false);


// -----------------------------------------------------------------------------
// REGION | Suite - Relative Entry and Clamping
// -----------------------------------------------------------------------------

na_suite('Relative entry and clamping');
na_expect('+200 on 2400',          Arithmetic.na_resolve_field_value('+200', { currentValue: 2400 }).value, 2600);
na_expect('-50 on 1700',           Arithmetic.na_resolve_field_value('-50',  { currentValue: 1700 }).value, 1650);
na_expect('/3 on 2400',            Arithmetic.na_resolve_field_value('/3',   { currentValue: 2400 }).value, 800);
na_expect('*2 on 900',             Arithmetic.na_resolve_field_value('*2',   { currentValue: 900 }).value, 1800);
na_expect('relative flagged',      Arithmetic.na_resolve_field_value('+200', { currentValue: 2400 }).wasRelative, true);
na_expect('signed field literal -',
          Arithmetic.na_resolve_field_value('-50', { currentValue: 0, allowRelativeMinus: false }).value, -50);
na_expect('signed field relative +',
          Arithmetic.na_resolve_field_value('+50', { currentValue: 100, allowRelativeMinus: false }).value, 150);
na_expect('no current value, +200', Arithmetic.na_resolve_field_value('+200', {}).value, 200);
na_expect('no current value, *3',   Arithmetic.na_resolve_field_value('*3', {}).ok, false);
na_expect('full expression wins',   Arithmetic.na_resolve_field_value('1700-50', { currentValue: 9999 }).value, 1650);
na_expect('clamp low',              Arithmetic.na_resolve_field_value('100',  { min: 300, max: 4000 }).value, 300);
na_expect('clamp high',             Arithmetic.na_resolve_field_value('9000', { min: 300, max: 4000 }).value, 4000);
na_expect('clamp flagged',          Arithmetic.na_resolve_field_value('9000', { min: 300, max: 4000 }).wasClamped, true);
na_expect('in range unflagged',     Arithmetic.na_resolve_field_value('1700', { min: 300, max: 4000 }).wasClamped, false);
na_expect('relative then clamped',
          Arithmetic.na_resolve_field_value('+9000', { currentValue: 1700, min: 300, max: 4000 }).value, 4000);
na_expect('formatted text',         Arithmetic.na_resolve_field_value('2400/7', {}).text, '342.857');


// -----------------------------------------------------------------------------
// REGION | Suite - Shared Slider Wiring
// -----------------------------------------------------------------------------

na_suite('Shared slider wiring');

// HELPER FUNCTION | Mount a Slider Against the Real Event Wiring
// ------------------------------------------------------------
function na_mount_slider(descriptor) {
    const slider  = na_make_element(descriptor.id + '-slider');
    const input   = na_make_element(descriptor.id + '-input');
    const display = na_make_element(descriptor.id + '-display');
    [slider, input].forEach((element) => {
        element.min   = descriptor.min;
        element.max   = descriptor.max;
        element.step  = descriptor.step;
        element.value = descriptor.default;
    });
    display.textContent = descriptor.default + descriptor.unit;
    input.setAttribute('title', 'the arithmetic hint');                         // <-- Stands in for NA_ARITHMETIC_HINT
    const emitted = [];
    Events.na_attachSliderListeners(descriptor, (id, value) => emitted.push(value));
    return { slider, input, display, emitted };
}
// ---------------------------------------------------------------

const NA_WIDTH = { id: 'width_mm', label: 'Width', unit: 'mm', type: 'slider', min: 300, max: 4000, step: 5, default: 1700 };

let control = na_mount_slider(NA_WIDTH);
control.input.fire('focus');
control.input.value = '1700-50';
control.input.fire('change');
na_expect('emits 1650',            control.emitted.pop(), 1650);
na_expect('field reads 1650',      control.input.value, '1650');
na_expect('display reads 1650mm',  control.display.textContent, '1650mm');
na_expect('slider follows',        control.slider.value, 1650);

control = na_mount_slider(Object.assign({}, NA_WIDTH, { id: 'wire_a', default: 2400 }));
control.input.fire('focus');
control.input.value = '2400+(100+100+100+100)';
control.input.fire('change');
na_expect('bracketed sum commits', control.emitted.pop(), 2800);

// Consecutive relative entries must stack rather than repeat, so the committed
// value is refreshed after every commit and not only on focus.
control = na_mount_slider(Object.assign({}, NA_WIDTH, { id: 'wire_b', default: 2400 }));
control.input.fire('focus');
control.input.value = '+200'; control.input.fire('change');
na_expect('first +200',            control.emitted[control.emitted.length - 1], 2600);
control.input.value = '+200'; control.input.fire('change');
na_expect('second +200 stacks',    control.emitted[control.emitted.length - 1], 2800);

// The DOM is authoritative for the clamp range: width_mm is declared max 4000
// but widened to 8000 in multi-leaf door modes.
control = na_mount_slider(Object.assign({}, NA_WIDTH, { id: 'wire_c' }));
control.input.max = 8000;
control.slider.max = 8000;
control.input.fire('focus');
control.input.value = '6000'; control.input.fire('change');
na_expect('live max honoured',     control.emitted.pop(), 6000);
control.input.value = '9000'; control.input.fire('change');
na_expect('clamps to live max',    control.emitted.pop(), 8000);
control.input.value = '10'; control.input.fire('change');
na_expect('clamps to min',         control.emitted.pop(), 300);

// A missing attribute must fall back to the descriptor, never read as zero.
control = na_mount_slider(Object.assign({}, NA_WIDTH, { id: 'wire_d' }));
delete control.input.attrs.min;
delete control.input.attrs.max;
control.input.fire('focus');
control.input.value = '1700-50'; control.input.fire('change');
na_expect('absent attrs fall back to descriptor', control.emitted.pop(), 1650);

// An unreadable entry must restore the previous value, never emit NaN.
control = na_mount_slider(Object.assign({}, NA_WIDTH, { id: 'wire_e' }));
control.input.fire('focus');
control.input.value = '1700-'; control.input.fire('change');
na_expect('bad entry emits nothing',  control.emitted.length, 0);
na_expect('bad entry restores field', control.input.value, '1700');
na_expect('bad entry is flagged',     control.input.classList.contains('na-input-error'), true);
na_expect('reason goes in the tooltip', control.input.getAttribute('title'), 'Expression is incomplete');
control.input.fire('input');
na_expect('typing clears the flag',   control.input.classList.contains('na-input-error'), false);
na_expect('tooltip restored',         control.input.getAttribute('title'), 'the arithmetic hint');
control.input.value = 'abc'; control.input.fire('change');
na_expect('letters emit nothing',     control.emitted.length, 0);
control.input.value = ''; control.input.fire('change');
na_expect('empty emits nothing',      control.emitted.length, 0);

// Signed controls keep a literal negative; unsigned ones read it as relative.
const NA_OFFSET = { id: 'meeting_rail_offset_mm', label: 'Offset', unit: 'mm', type: 'slider', min: -600, max: 600, step: 5, default: 0 };
control = na_mount_slider(NA_OFFSET);
control.input.fire('focus');
control.input.value = '-50'; control.input.fire('change');
na_expect('signed field literal -50', control.emitted.pop(), -50);
control.input.value = '-200-100'; control.input.fire('change');
na_expect('signed field expression',  control.emitted.pop(), -300);

control = na_mount_slider(Object.assign({}, NA_WIDTH, { id: 'wire_f' }));
control.input.fire('focus');
control.input.value = '-50'; control.input.fire('change');
na_expect('unsigned field relative -50', control.emitted.pop(), 1650);

// Arrow stepping replaces what type="number" used to provide natively.
control = na_mount_slider(Object.assign({}, NA_WIDTH, { id: 'wire_g' }));
control.input.fire('focus');
control.input.fire('keydown', { key: 'ArrowUp',   shiftKey: false, preventDefault: () => {} });
na_expect('ArrowUp steps by step',    control.emitted.pop(), 1705);
control.input.fire('keydown', { key: 'ArrowDown', shiftKey: false, preventDefault: () => {} });
na_expect('ArrowDown steps by step',  control.emitted.pop(), 1700);
control.input.fire('keydown', { key: 'ArrowUp',   shiftKey: true,  preventDefault: () => {} });
na_expect('Shift multiplies by ten',  control.emitted.pop(), 1750);
control.input.value = '3999';
control.input.fire('keydown', { key: 'ArrowUp',   shiftKey: true,  preventDefault: () => {} });
na_expect('stepping clamps at max',   control.emitted.pop(), 4000);
control.input.fire('keydown', { key: 'a', shiftKey: false, preventDefault: () => {} });
na_expect('other keys ignored',       control.emitted.length, 0);

// Dragging the range must keep working, and must feed relative entry.
control = na_mount_slider(Object.assign({}, NA_WIDTH, { id: 'wire_h' }));
control.slider.value = '2200';
control.slider.fire('input');
na_expect('drag emits',               control.emitted.pop(), 2200);
na_expect('drag fills the field',     control.input.value, '2200');
control.slider.value = '2000'; control.slider.fire('input'); control.emitted.pop();
control.input.fire('focus');
control.input.value = '+100'; control.input.fire('change');
na_expect('relative after a drag',    control.emitted.pop(), 2100);


// -----------------------------------------------------------------------------
// REGION | Suite - EQ-Number Field
// -----------------------------------------------------------------------------

na_suite('EQ-number field');

const na_eq_descriptor = { id: 'double_door_active_leaf_width_mm', label: 'Active Leaf Width', type: 'eq_number', default: 'EQ' };
const na_eq_input      = na_make_element(na_eq_descriptor.id + '-eqnumber');
na_eq_input.value      = na_eq_descriptor.default;
const na_eq_emitted    = [];
Events.na_attachEqNumberListener(na_eq_descriptor, (id, value) => na_eq_emitted.push(value));

na_eq_input.fire('focus');
na_eq_input.value = '1700/2'; na_eq_input.fire('change');
na_expect('divides',               na_eq_emitted.pop(), 850);
na_expect('shows the result',      na_eq_input.value, 850);
na_eq_input.fire('focus');
na_eq_input.value = '+50'; na_eq_input.fire('change');
na_expect('relative entry',        na_eq_emitted.pop(), 900);
na_eq_input.value = 'eq'; na_eq_input.fire('change');
na_expect('EQ literal preserved',  na_eq_emitted.pop(), 'EQ');
na_eq_input.value = '((('; na_eq_input.fire('change');
na_expect('bad entry falls to EQ', na_eq_emitted.pop(), 'EQ');


// -----------------------------------------------------------------------------
// REGION | Suite - Interior Door Tab Helpers
// -----------------------------------------------------------------------------

na_suite('Interior Door tab helpers');

// HELPER FUNCTION | Build a Detached Field for the Interior Door Helpers
// ------------------------------------------------------------
function na_door_field(value, attributes) {
    const classes = new Set();
    return {
        value       : value,
        dataset     : {},
        getAttribute: (name) => (attributes && attributes[name] !== undefined ? String(attributes[name]) : null),
        classList   : {
            add     : (name) => classes.add(name),
            remove  : (name) => classes.delete(name),
            contains: (name) => classes.has(name)
        }
    };
}
// ---------------------------------------------------------------

const NA_DOOR_DESCRIPTOR = { id: 'Na__DoorConfig__StructuralOpeningWidth_mm', min: 400, max: 3000, step: 5, unit: 'mm' };

na_expect('subtract',      InteriorDoor.na_resolve_typed_value(na_door_field('1700-50'), NA_DOOR_DESCRIPTOR, 1700).value, 1650);
na_expect('divide',        InteriorDoor.na_resolve_typed_value(na_door_field('2400/3'),  NA_DOOR_DESCRIPTOR, 2400).value, 800);
na_expect('brackets',      InteriorDoor.na_resolve_typed_value(na_door_field('900+(50+50)'), NA_DOOR_DESCRIPTOR, 900).value, 1000);
na_expect('relative +200', InteriorDoor.na_resolve_typed_value(na_door_field('+200'), NA_DOOR_DESCRIPTOR, 2400).value, 2600);
na_expect('relative -50',  InteriorDoor.na_resolve_typed_value(na_door_field('-50'),  NA_DOOR_DESCRIPTOR, 900).value, 850);
na_expect('clamp max',     InteriorDoor.na_resolve_typed_value(na_door_field('9000'), NA_DOOR_DESCRIPTOR, 900).value, 3000);
na_expect('clamp min',     InteriorDoor.na_resolve_typed_value(na_door_field('50'),   NA_DOOR_DESCRIPTOR, 900).value, 400);
na_expect('live widened max wins',
          InteriorDoor.na_resolve_typed_value(na_door_field('4500', { min: 400, max: 5000, step: 5 }), NA_DOOR_DESCRIPTOR, 900).value, 4500);
na_expect('trailing operator rejected', InteriorDoor.na_resolve_typed_value(na_door_field('1700-'), NA_DOOR_DESCRIPTOR, 900).ok, false);
na_expect('letters rejected',           InteriorDoor.na_resolve_typed_value(na_door_field('abc'),   NA_DOOR_DESCRIPTOR, 900).ok, false);
na_expect('empty rejected',             InteriorDoor.na_resolve_typed_value(na_door_field(''),      NA_DOOR_DESCRIPTOR, 900).ok, false);

// The live-typing guard. '+200' passes the plain-number test at '+2', so a
// leading operator has to be excluded separately or the door would jump to 2mm
// mid-keystroke.
na_expect('plain number types live',
          InteriorDoor.na_is_plain_number_text('1700') && !InteriorDoor.na_starts_with_operator('1700'), true);
na_expect('+2 held back',       InteriorDoor.na_starts_with_operator('+2'), true);
na_expect('/3 held back',       InteriorDoor.na_starts_with_operator('/3'), true);
na_expect('-50 held back',      InteriorDoor.na_starts_with_operator('-50'), true);
na_expect('half-typed not plain', InteriorDoor.na_is_plain_number_text('1700-'), false);

const na_arrow_up   = { key: 'ArrowUp',   shiftKey: false };
const na_arrow_down = { key: 'ArrowDown', shiftKey: false };
const na_shift_up   = { key: 'ArrowUp',   shiftKey: true  };
na_expect('step up',        InteriorDoor.na_resolve_step_key(na_arrow_up,   na_door_field('900'),  NA_DOOR_DESCRIPTOR, 900), 905);
na_expect('step down',      InteriorDoor.na_resolve_step_key(na_arrow_down, na_door_field('900'),  NA_DOOR_DESCRIPTOR, 900), 895);
na_expect('shift step',     InteriorDoor.na_resolve_step_key(na_shift_up,   na_door_field('900'),  NA_DOOR_DESCRIPTOR, 900), 950);
na_expect('step clamps',    InteriorDoor.na_resolve_step_key(na_shift_up,   na_door_field('2990'), NA_DOOR_DESCRIPTOR, 2990), 3000);
na_expect('other key null', InteriorDoor.na_resolve_step_key({ key: 'a' },  na_door_field('900'),  NA_DOOR_DESCRIPTOR, 900), null);
na_expect('steps from committed when mid-expression',
          InteriorDoor.na_resolve_step_key(na_arrow_up, na_door_field('900-'), NA_DOOR_DESCRIPTOR, 900), 905);
na_expect('formats integers', InteriorDoor.na_format_number(1650), '1650');
na_expect('formats decimals', InteriorDoor.na_format_number(342.857142), '342.857');


// -----------------------------------------------------------------------------
// REGION | Result
// -----------------------------------------------------------------------------

console.log('\n' + '='.repeat(60));
console.log(na_pass + ' passed, ' + na_fail + ' failed');
console.log('='.repeat(60) + '\n');
process.exit(na_fail === 0 ? 0 : 1);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
