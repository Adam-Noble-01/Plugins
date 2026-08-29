/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - COMPONENT NAME FIELD SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__ComponentName__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for the WINDOW INFO "Component Name" field -
                the dialog half of the V1.5.4 component naming feature.
   CREATED    : 28-Aug-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__ComponentName__Spec__.js"

   Exits 0 when everything passes, 1 otherwise.

   WHY THIS EXISTS:
   The field appends a tail to a component name whose HEAD is a machine
   contract read by TrueVision and ValeVision. The expensive failure mode is
   not a wrong tail - it is the dialog ever composing, editing or re-sending
   the head. These assertions pin down that JS only ever reads the head Ruby
   sends it, plus the commit triggers (typing / Enter / blur) that decide when
   a rename actually reaches SketchUp.

   The suite loads the SHIPPED bridge unmodified against a minimal DOM stub,
   so it tests what actually runs in the dialog.

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

const na_registry = {};

// HELPER FUNCTION | Create and Register a Fake Element
// ------------------------------------------------------------
function na_make_element(id) {
    const classes = new Set();
    const element = {
        id            : id,
        value         : '',
        children      : [],
        className     : '',
        disabled      : false,
        listeners     : {},
        classList     : {
            add     : (name) => classes.add(name),
            remove  : (name) => classes.delete(name),
            contains: (name) => classes.has(name)
        },
        appendChild     : (child) => { element.children.push(child); return child; },
        addEventListener: (name, handler) => {
            element.listeners[name] = element.listeners[name] || [];
            element.listeners[name].push(handler);
        },
        fire            : (name, event) => (element.listeners[name] || [])
                            .forEach((handler) => handler(event || { preventDefault: () => {} }))
    };

    // textContent behaves like the browser's: reading concatenates the
    // subtree, writing to '' clears the children the preview builder appends.
    let ownText = '';
    Object.defineProperty(element, 'textContent', {
        get: () => (element.children.length
                    ? element.children.map((child) => child.textContent).join('')
                    : ownText),
        set: (value) => { ownText = String(value); element.children = []; }
    });

    if (id) na_registry[id] = element;
    return element;
}
// ---------------------------------------------------------------

// The elements the bridge reaches for by id.
[
    'na-info-component-name',
    'na-info-component-name-preview',
    'na-info-description',
    'na-info-window-id',
    'na-info-created',
    'na-info-modified',
    'na-window-info',
    'na-btn-create',
    'na-btn-update',
    'na-btn-create-at-measurement',
    'na-status-bar',
    'na-status-message'
].forEach(na_make_element);

// Controllable timers so the debounce can be flushed instantly.
const na_timers = [];
let na_timer_seq = 0;

global.setTimeout = function (fn, delay) {
    na_timer_seq += 1;
    na_timers.push({ id: na_timer_seq, fn: fn, delay: delay });
    return na_timer_seq;
};
global.clearTimeout = function (id) {
    const index = na_timers.findIndex((timer) => timer.id === id);
    if (index >= 0) na_timers.splice(index, 1);
};

// HELPER FUNCTION | Run Every Pending Timer Callback
// ------------------------------------------------------------
function na_flush_timers() {
    const due = na_timers.splice(0, na_timers.length);
    due.forEach((timer) => timer.fn());
}
// ---------------------------------------------------------------

const na_dom_ready = [];

global.window   = {};
global.document = {
    getElementById  : (id) => na_registry[id] || null,
    querySelector   : () => null,
    createElement   : () => na_make_element(null),
    addEventListener: (name, handler) => {
        if (name === 'DOMContentLoaded') na_dom_ready.push(handler);
    }
};

// Records every rename call the bridge makes.
const na_sent = [];
global.sketchup = {
    na_setComponentName     : (json) => na_sent.push(JSON.parse(json)),
    na_requestSashHornAssets: () => {},
    na_jsLog                : () => {}
};

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Load the Shipped Bridge
// -----------------------------------------------------------------------------

function na_read(relativePath) {
    return fs.readFileSync(path.join(NA_MODULES, relativePath), 'utf8');
}

const Bridge   = {};
const NA_QUIET = console.log;
console.log = () => {};                                                         // <-- Silence the bridge's own logging
eval(na_read('20__System__WindowSystem/Na__AssemblyStudio__WindowSystem__UiSystem__Bridge__.js') + `
    Bridge.na_readComponentName        = na_readComponentName;
    Bridge.na_commitComponentName      = na_commitComponentName;
    Bridge.na_updateComponentNamePreview = na_updateComponentNamePreview;
`);
console.log = NA_QUIET;

na_dom_ready.forEach((handler) => handler());                                    // <-- Binds the field's input/keydown/blur listeners
na_timers.length = 0;                                                            // <-- Drop the sash-horn retry timer

const na_field   = na_registry['na-info-component-name'];
const na_preview = na_registry['na-info-component-name-preview'];

// HELPER FUNCTION | Push a Selection Payload Through the Real Ruby Entry Point
// ------------------------------------------------------------
function na_select(id, base, tail, description) {
    na_sent.length = 0;
    global.window.na_setInitialConfig(JSON.stringify({
        windowMetadata: [{
            WindowUniqueId         : id,
            WindowComponentBaseName: base,
            WindowComponentName    : tail,
            WindowDescription      : description || '',
            CreatedDate            : '2026-08-28 11:22:01',
            LastModified           : '2026-08-28 11:22:01'
        }],
        windowConfiguration: {}
    }));
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite - Loading a Selected Component
// -----------------------------------------------------------------------------

na_suite('Loading a selected component');

na_select('AWN019', 'AWN019__Window__', 'GroundFloor__BayWindow');
na_expect('field shows the stored tail',   na_field.value, 'GroundFloor__BayWindow');
na_expect('preview shows the full name',   na_preview.textContent, 'AWN019__Window__GroundFloor__BayWindow');
na_expect('description is independent',    na_registry['na-info-description'].value, '');
na_expect('load sends no rename',          na_sent.length, 0);

na_select('AWN020', 'AWN020__Window__', '');
na_expect('unnamed component clears field', na_field.value, '');
na_expect('preview is head only',           na_preview.textContent, 'AWN020__Window__');

// A pre-V1.5.4 payload carries no name keys at all.
na_sent.length = 0;
global.window.na_setInitialConfig(JSON.stringify({
    windowMetadata: [{ WindowUniqueId: 'AWN021', WindowDescription: 'legacy notes' }],
    windowConfiguration: {}
}));
na_expect('legacy payload leaves field empty', na_field.value, '');
na_expect('legacy payload hides preview',      na_preview.textContent, '');

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite - Exterior Door Products Share the Field
// -----------------------------------------------------------------------------

na_suite('Exterior door products share the field');

[
    ['ADR004', 'ADR004__ExteriorDoubleDoor__', 'Orangery__CentrePair'],
    ['ADR005', 'ADR005__ExteriorSingleDoor__', 'Utility'],
    ['ADR006', 'ADR006__SlidingDoor__',        'Rear__Terrace'],
    ['ADR007', 'ADR007__BifoldDoor__',         'Garden__Room']
].forEach(function (product) {
    na_select(product[0], product[1], product[2]);
    na_expect('preview head is the door type: ' + product[1],
              na_preview.textContent, product[1] + product[2]);
});

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite - Commit Triggers
// -----------------------------------------------------------------------------

na_suite('Commit triggers');

na_select('AWN019', 'AWN019__Window__', 'Lounge');

// Typing repaints the preview immediately but holds the rename back.
na_field.value = 'Loung';
na_field.fire('input');
na_expect('preview follows every keystroke', na_preview.textContent, 'AWN019__Window__Loung');
na_expect('typing alone sends nothing',      na_sent.length, 0);

na_field.value = 'Lounge__Bay';
na_field.fire('input');
na_expect('still debounced', na_sent.length, 0);

na_flush_timers();
na_expect('debounce fires one rename', na_sent.length, 1);
na_expect('rename payload', na_sent[0], { componentName: 'Lounge__Bay', itemId: 'AWN019' });

// Enter bypasses the debounce.
na_sent.length = 0;
na_field.value = 'Lounge__BayWindow';
na_field.fire('input');
let na_prevented = false;
na_field.fire('keydown', { key: 'Enter', preventDefault: () => { na_prevented = true; } });
na_expect('Enter renames immediately', na_sent.length, 1);
na_expect('Enter payload',             na_sent[0].componentName, 'Lounge__BayWindow');
na_expect('Enter suppresses default',  na_prevented, true);
na_flush_timers();
na_expect('Enter cancelled the pending debounce', na_sent.length, 1);

// A key that is not Enter must not commit.
na_sent.length = 0;
na_field.value = 'Lounge__BayWindow__Left';
na_field.fire('keydown', { key: 'a', preventDefault: () => {} });
na_expect('other keys do not commit', na_sent.length, 0);

// Blur commits whatever is in the field.
na_field.fire('blur');
na_expect('blur commits', na_sent.length, 1);
na_expect('blur payload',  na_sent[0].componentName, 'Lounge__BayWindow__Left');

// Committing an unchanged value is a no-op.
na_sent.length = 0;
na_field.fire('blur');
na_expect('unchanged value sends nothing', na_sent.length, 0);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite - Ruby Echo and Clearing
// -----------------------------------------------------------------------------

na_suite('Ruby echo and clearing');

na_select('AWN019', 'AWN019__Window__', 'Lounge');
na_field.value = 'Lounge/Bay:1';
na_field.fire('input');
na_flush_timers();
na_expect('unsanitised text is sent as typed', na_sent[0].componentName, 'Lounge/Bay:1');

// Ruby strips what SketchUp cannot carry and echoes the real name back.
global.window.na_receiveComponentName(JSON.stringify({
    componentName: 'LoungeBay1',
    fullName     : 'AWN019__Window__LoungeBay1'
}));
na_expect('field shows the sanitised name',   na_field.value, 'LoungeBay1');
na_expect('preview shows the sanitised name', na_preview.textContent, 'AWN019__Window__LoungeBay1');

// The echoed value becomes the new baseline, so a blur must not re-send it.
na_sent.length = 0;
na_field.fire('blur');
na_expect('echoed value is the new baseline', na_sent.length, 0);

// Deselecting must not leave the previous component's name behind.
global.window.na_clearCurrentWindow();
na_expect('deselect clears the field',   na_field.value, '');
na_expect('deselect clears the preview', na_preview.textContent, '');

na_sent.length = 0;
na_field.value = 'Orphan';
na_field.fire('input');
na_flush_timers();
na_expect('no rename without a selection', na_sent.length, 0);

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Result
// -----------------------------------------------------------------------------

console.log('\n' + na_pass + ' passed, ' + na_fail + ' failed');
process.exit(na_fail === 0 ? 0 : 1);

// endregion -------------------------------------------------------------------

/* =============================================================================
   END OF FILE
   ============================================================================= */
