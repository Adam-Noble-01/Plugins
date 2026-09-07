/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - MULLION LAYOUT SPEC
   =============================================================================

   FILE       : Na__AssemblyStudio__DevTools__MullionMath__Spec__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Regression suite for Na__MullionMath - the shared authority for
                where mullions sit and how wide each light therefore is.
   CREATED    : 07-Sep-2026

   HOW TO RUN (from anywhere, needs only Node - no install, no dependencies):

       node "65__Dev__DevTools/Na__AssemblyStudio__DevTools__MullionMath__Spec__.js"

   Exits 0 when everything passes, 1 on the first failing assertion set.

   WHY THIS EXISTS:
   Four producers - the 2D preview, the JS DXF fallback, the Ruby DXF stream
   and the SketchUp solid - each place mullions from the same offsets. If the
   layout drifts, a window is drawn one way and built another, and the user
   only finds out after it is in the model. The two properties that matter
   most are pinned here:

     * WITH OFFSETS OFF the output is byte-identical to the equal-lights
       formula every producer inlined before V1.6.0, so no existing window
       can move.
     * NO combination of slider values can make mullions cross, exceed the
       frame, or produce a zero-width light.

   The suite loads the SHIPPED source file unmodified - a `window` stub stands
   in for the browser - so this tests what actually runs in the dialog.

   ============================================================================= */

'use strict';

const fs   = require('fs');
const path = require('path');
const vm   = require('vm');


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
    if (condition) {
        na_pass += 1;
        return;
    }
    na_fail += 1;
    console.log('  FAIL  ' + label);
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Round to 6dp so Float Noise Never Fails a Comparison
// ------------------------------------------------------------
function na_round(value) {
    return Math.round(value * 1e6) / 1e6;
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
// REGION | Load the Shipped Module Against a Browser Stub
// -----------------------------------------------------------------------------

const NA_MULLION_MATH_PATH = path.join(
    NA_MODULES,
    '20__System__WindowSystem',
    'Na__AssemblyStudio__WindowSystem__Viewport__MullionMath__.js'
);

const na_sandbox = { window: {}, console: { log: function () {} } };
vm.createContext(na_sandbox);
vm.runInContext(fs.readFileSync(NA_MULLION_MATH_PATH, 'utf8'), na_sandbox, {
    filename: NA_MULLION_MATH_PATH
});

const MullionMath = na_sandbox.window.Na__MullionMath;

if (!MullionMath) {
    console.log('FATAL: Na__MullionMath did not attach to window');
    process.exit(1);
}

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Shared Fixtures
// -----------------------------------------------------------------------------

// The window from the reference photograph: 2800mm wide, 50mm frame all round,
// two mullions at 40mm splitting it into three lights.
const NA_INNER_LEFT   = 50;
const NA_INNER_WIDTH  = 2700;                                    // <-- 2800 - 50 left - 50 right
const NA_MULLION_W    = 40;

// HELPER FUNCTION | Legacy Equal-Lights Formula (the pre-V1.6.0 inline code)
// ------------------------------------------------------------
// Reproduced verbatim from what every producer used to inline, so the
// "offsets off changes nothing" claim is checked against the old code
// rather than against the new module's own even-layout branch.
function na_legacyLayout(innerLeft, innerWidth, count, mullionWidth) {
    const openingWidth = (innerWidth - (count * mullionWidth)) / (count + 1);
    const mullionXs = [];
    const openingXs = [];
    for (let m = 1; m <= count; m += 1) {
        mullionXs.push(innerLeft + (m * openingWidth) + ((m - 1) * mullionWidth));
    }
    for (let i = 0; i <= count; i += 1) {
        openingXs.push(innerLeft + (i * (openingWidth + mullionWidth)));
    }
    return { openingWidth: openingWidth, mullionXs: mullionXs, openingXs: openingXs };
}
// ---------------------------------------------------------------

// HELPER FUNCTION | Reduce a Layout to Rounded Position Arrays
// ------------------------------------------------------------
function na_positions(layout) {
    return {
        mullionXs : layout.mullions.map(m => na_round(m.x)),
        openingXs : layout.openings.map(o => na_round(o.x)),
        widths    : layout.openings.map(o => na_round(o.width))
    };
}
// ---------------------------------------------------------------

// endregion -------------------------------------------------------------------


// -----------------------------------------------------------------------------
// REGION | Suite 1 - Offsets Off Reproduces the Legacy Layout Exactly
// -----------------------------------------------------------------------------

na_suite('Legacy parity (no offsets)');

[0, 1, 2, 3, 6].forEach(function (count) {
    const legacy = na_legacyLayout(NA_INNER_LEFT, NA_INNER_WIDTH, count, NA_MULLION_W);
    const layout = MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, count, NA_MULLION_W, []);
    const actual = na_positions(layout);

    na_expect(count + ' mullions - mullion positions', actual.mullionXs, legacy.mullionXs.map(na_round));
    na_expect(count + ' mullions - opening positions', actual.openingXs, legacy.openingXs.map(na_round));
    na_expect(count + ' mullions - all lights equal',
              actual.widths,
              legacy.openingXs.map(() => na_round(legacy.openingWidth)));
});

// An all-zero offsets array must be indistinguishable from no array at all.
na_expect('zero offsets == no offsets',
          na_positions(MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [0, 0])),
          na_positions(MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [])));

// Mullion index is 1-based (matches the slider numbering); opening index 0-based.
const na_indexLayout = MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, []);
na_expect('mullion indices are 1-based', na_indexLayout.mullions.map(m => m.index), [1, 2]);
na_expect('opening indices are 0-based', na_indexLayout.openings.map(o => o.index), [0, 1, 2]);
na_expect('openings === mullions + 1',   na_indexLayout.openings.length, na_indexLayout.mullions.length + 1);


// -----------------------------------------------------------------------------
// REGION | Suite 2 - The Reference Window (wide centre light)
// -----------------------------------------------------------------------------

na_suite('Reference window - wide centre, narrow flanks');

// Equal thirds put the mullions at 50+873.33 and 50+1786.67. Pull the first
// 300mm left and push the second 300mm right to widen the centre light.
const na_wideCentre = MullionMath.na_computeMullionLayout(
    NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [-300, 300]
);
const na_wideWidths = na_wideCentre.openings.map(o => na_round(o.width));

na_assert('left light narrowed',   na_wideWidths[0] < 873.34);
na_assert('centre light widened',  na_wideWidths[1] > 873.34);
na_assert('right light narrowed',  na_wideWidths[2] < 873.34);
na_expect('flanking lights stay symmetrical', na_wideWidths[0], na_wideWidths[2]);
na_expect('centre gains both nudges', na_round(na_wideWidths[1] - 873.333333), 600);
na_expect('lights + mullions still fill the frame',
          na_round(na_wideCentre.openings.reduce((sum, o) => sum + o.width, 0) + (2 * NA_MULLION_W)),
          NA_INNER_WIDTH);

// A single mullion nudged right widens the left light by exactly the nudge.
const na_singleNudge = MullionMath.na_computeMullionLayout(
    NA_INNER_LEFT, NA_INNER_WIDTH, 1, NA_MULLION_W, [250]
);
na_expect('one mullion - left light grows by the nudge',
          na_round(na_singleNudge.openings[0].width),
          na_round(((NA_INNER_WIDTH - NA_MULLION_W) / 2) + 250));
na_expect('one mullion - right light shrinks by the nudge',
          na_round(na_singleNudge.openings[1].width),
          na_round(((NA_INNER_WIDTH - NA_MULLION_W) / 2) - 250));


// -----------------------------------------------------------------------------
// REGION | Suite 3 - Clamping: mullions can never cross or escape the frame
// -----------------------------------------------------------------------------

na_suite('Clamping invariants');

const NA_MIN = MullionMath.NA_MULLION_MIN_OPENING_MM;
na_expect('minimum light constant', NA_MIN, 50);

// HELPER FUNCTION | Assert Every Structural Invariant Holds for One Layout
// ------------------------------------------------------------
function na_assertInvariants(label, layout, innerLeft, innerWidth, mullionWidth) {
    const innerRight = innerLeft + innerWidth;
    let ordered = true;
    let inside  = true;
    let cursor  = innerLeft;

    layout.mullions.forEach(function (mullion) {
        if (na_round(mullion.x) < na_round(cursor)) ordered = false;
        if (na_round(mullion.x) < na_round(innerLeft)) inside = false;
        if (na_round(mullion.x + mullion.width) > na_round(innerRight)) inside = false;
        cursor = mullion.x + mullion.width;
    });

    const allPositive = layout.openings.every(o => na_round(o.width) >= NA_MIN);
    const totalSpan   = layout.openings.reduce((sum, o) => sum + o.width, 0) +
                        (layout.mullions.length * mullionWidth);

    na_assert(label + ' - mullions stay ordered',        ordered);
    na_assert(label + ' - mullions stay inside frame',   inside);
    na_assert(label + ' - every light >= minimum',       allPositive);
    na_expect(label + ' - lights + mullions fill frame', na_round(totalSpan), na_round(innerWidth));
}
// ---------------------------------------------------------------

na_assertInvariants('both slammed left',
    MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [-2000, -2000]),
    NA_INNER_LEFT, NA_INNER_WIDTH, NA_MULLION_W);

na_assertInvariants('both slammed right',
    MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [2000, 2000]),
    NA_INNER_LEFT, NA_INNER_WIDTH, NA_MULLION_W);

na_assertInvariants('crossing attempt (first right, second left)',
    MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [2000, -2000]),
    NA_INNER_LEFT, NA_INNER_WIDTH, NA_MULLION_W);

na_assertInvariants('six mullions all slammed left',
    MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 6, NA_MULLION_W, [-2000, -2000, -2000, -2000, -2000, -2000]),
    NA_INNER_LEFT, NA_INNER_WIDTH, NA_MULLION_W);

na_assertInvariants('six mullions all slammed right',
    MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 6, NA_MULLION_W, [2000, 2000, 2000, 2000, 2000, 2000]),
    NA_INNER_LEFT, NA_INNER_WIDTH, NA_MULLION_W);

na_assertInvariants('alternating extremes',
    MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 3, NA_MULLION_W, [2000, -2000, 1500]),
    NA_INNER_LEFT, NA_INNER_WIDTH, NA_MULLION_W);

// The left-most mullion slammed left leaves exactly the minimum light.
const na_slammedLeft = MullionMath.na_computeMullionLayout(
    NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [-2000, -2000]
);
na_expect('first light clamps to the minimum', na_round(na_slammedLeft.openings[0].width), NA_MIN);
na_expect('second light clamps to the minimum', na_round(na_slammedLeft.openings[1].width), NA_MIN);

// The right-most mullion slammed right leaves exactly the minimum light.
const na_slammedRight = MullionMath.na_computeMullionLayout(
    NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [2000, 2000]
);
na_expect('last light clamps to the minimum', na_round(na_slammedRight.openings[2].width), NA_MIN);

// Non-numeric entries mean "no nudge for this mullion", never NaN.
const na_sparse = MullionMath.na_computeMullionLayout(
    NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [null, 200]
);
na_assert('null offset does not poison the layout',
          na_sparse.openings.every(o => Number.isFinite(o.width)));
na_expect('null offset leaves mullion 1 where it was',
          na_round(na_sparse.mullions[0].x),
          na_round(na_legacyLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W).mullionXs[0]));


// -----------------------------------------------------------------------------
// REGION | Suite 4 - Degenerate frames fall back to the legacy layout
// -----------------------------------------------------------------------------

na_suite('Degenerate frames');

// 200mm of inner width cannot hold 2x40mm mullions plus 3x50mm lights, so the
// offsets are dropped and the equal-lights (negative-width) output is
// returned - the same thing the tool produced before this feature, and what
// the validator already reports as "opening too narrow".
const na_tooNarrow = MullionMath.na_computeMullionLayout(50, 200, 2, NA_MULLION_W, [-500, 500]);
na_expect('too-narrow frame ignores offsets',
          na_positions(na_tooNarrow),
          na_positions(MullionMath.na_computeMullionLayout(50, 200, 2, NA_MULLION_W, [])));

na_expect('zero mullions yields one full-width light',
          na_positions(MullionMath.na_computeMullionLayout(50, 2700, 0, NA_MULLION_W, [500])),
          { mullionXs: [], openingXs: [50], widths: [2700] });

// Exactly at the feasibility threshold the offsets still apply.
const na_exactFit = (2 * NA_MULLION_W) + (3 * NA_MIN);
na_assertInvariants('frame exactly at the feasibility threshold',
    MullionMath.na_computeMullionLayout(0, na_exactFit, 2, NA_MULLION_W, [-500, 500]),
    0, na_exactFit, NA_MULLION_W);


// -----------------------------------------------------------------------------
// REGION | Suite 5 - Config gate (mullion_offsets_enabled)
// -----------------------------------------------------------------------------

na_suite('Config gate and collection');

const na_configWithNudges = {
    mullions               : 2,
    mullion_width_mm       : 40,
    mullion_offsets_enabled: true,
    mullion_offset_1_mm    : -300,
    mullion_offset_2_mm    : 300
};

na_expect('collects the nudges when enabled',
          MullionMath.na_collectMullionOffsets(na_configWithNudges, 2), [-300, 300]);

na_expect('toggle off drops every nudge',
          MullionMath.na_collectMullionOffsets(
              Object.assign({}, na_configWithNudges, { mullion_offsets_enabled: false }), 2), []);

// An ABSENT toggle means a pre-V1.6.0 window, which must build as it always
// did. This is deliberately the opposite of Na__GlazebarMath's rule, whose
// pool predates its own toggle.
const na_legacyConfig = { mullions: 2, mullion_width_mm: 40, mullion_offset_1_mm: -300 };
na_expect('absent toggle drops every nudge (pre-V1.6.0 config)',
          MullionMath.na_collectMullionOffsets(na_legacyConfig, 2), []);

na_expect('collection is capped at the mullion count',
          MullionMath.na_collectMullionOffsets(na_configWithNudges, 1), [-300]);

na_expect('missing keys collect as zero',
          MullionMath.na_collectMullionOffsets(
              { mullions: 3, mullion_offsets_enabled: true, mullion_offset_2_mm: 120 }, 3),
          [0, 120, 0]);

na_expect('zero count collects nothing', MullionMath.na_collectMullionOffsets(na_configWithNudges, 0), []);
na_expect('null config collects nothing', MullionMath.na_collectMullionOffsets(null, 2), []);

// The config wrapper must agree with the explicit call.
na_expect('resolver matches the explicit call',
          na_positions(MullionMath.na_resolveMullionLayoutFromConfig(na_configWithNudges, NA_INNER_LEFT, NA_INNER_WIDTH)),
          na_positions(MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [-300, 300])));

na_expect('a pre-V1.6.0 config resolves to equal lights',
          na_positions(MullionMath.na_resolveMullionLayoutFromConfig(na_legacyConfig, NA_INNER_LEFT, NA_INNER_WIDTH)),
          na_positions(MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, [])));


// -----------------------------------------------------------------------------
// REGION | Suite 6 - Narrowest-light query (feeds the validator)
// -----------------------------------------------------------------------------

na_suite('Narrowest light');

na_expect('equal lights report the shared width',
          na_round(MullionMath.na_minimumOpeningWidth(
              MullionMath.na_computeMullionLayout(NA_INNER_LEFT, NA_INNER_WIDTH, 2, NA_MULLION_W, []))),
          na_round((NA_INNER_WIDTH - (2 * NA_MULLION_W)) / 3));

na_expect('unequal lights report the smallest',
          na_round(MullionMath.na_minimumOpeningWidth(na_wideCentre)),
          na_wideWidths[0]);

na_expect('no mullions reports the full inner width',
          MullionMath.na_minimumOpeningWidth(
              MullionMath.na_computeMullionLayout(50, 2700, 0, NA_MULLION_W, [])), 2700);

na_expect('an empty layout reports zero', MullionMath.na_minimumOpeningWidth(null), 0);


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
