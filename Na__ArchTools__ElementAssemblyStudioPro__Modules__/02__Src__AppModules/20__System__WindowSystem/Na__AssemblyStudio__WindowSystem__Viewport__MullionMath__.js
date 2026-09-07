/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - MULLION MATH (SHARED LAYOUT HELPERS)
   =============================================================================
   FILE       : Na__AssemblyStudio__WindowSystem__Viewport__MullionMath__.js
   NAMESPACE  : window.Na__MullionMath
   AUTHOR     : Noble Architecture
   PURPOSE    : The single authority for where mullions sit and how wide each
                opening therefore is. Consumed by the WindowSystem SVG
                generator (2D preview), the JS DXF exporter, and the viewport
                validator. Mirrored in Ruby by
                GeometryBuilders.na_compute_mullion_layout (3D) and
                DxfExporter.na_compute_mullion_layout_dxf (DXF stream) so all
                four representations agree on the same numbers.

   WHY THIS EXISTS
   Before V1.6.0 every producer inlined the same two lines:

       openingWidth = (innerWidth - count * mullionWidth) / (count + 1)
       mullionX     = innerLeft + m * openingWidth + (m - 1) * mullionWidth

   which hard-coded equal lights. Real windows are rarely equal - the common
   domestic three-light has a wide fixed centre flanked by two narrow
   openers. Unequal lights mean openings can no longer share one width, so
   the layout has to be computed once and handed round as a list.

   PUBLIC API
   - na_collectMullionOffsets(config, count)
       Gathers `mullion_offset_N_mm` (N = 1-based) into a 0-indexed numeric
       array of length `count`. Returns [] unless `mullion_offsets_enabled`
       is explicitly true.

   - na_computeMullionLayout(innerLeft, innerWidth, count, mullionWidth, offsetsMm)
       Returns { mullions: [{index, x, width}], openings: [{index, x, width}] }.
       Mullion `index` is 1-BASED to match the slider numbering and the
       `(1..count)` loops in every producer; opening `index` is 0-based to
       match the removal-key numbering. `x` is a left edge throughout.

   OFFSET SEMANTICS
   Each offset is a signed nudge in millimetres away from the equal-lights
   position. Positive drives that mullion RIGHT, negative LEFT. Zero (or the
   toggle off) reproduces the pre-V1.6.0 layout exactly, which is what keeps
   every window built before this feature rendering unchanged.

   ============================================================================= */

const Na__MullionMath = (function () {

    // CONSTANT | Narrowest Light the Clamp Will Leave Between Mullions
    // ---------------------------------------------------------------
    // A floor, not a design rule. It exists so a dragged slider can never
    // produce a zero-width or inverted opening - which reads as a missing
    // light in the preview and throws when SketchUp is asked to build a
    // face from it. Whether an opening is wide enough to hold a CASEMENT
    // is a separate, larger limit that Na__Viewport__Validation reports as
    // a user-facing warning.
    const NA_MULLION_MIN_OPENING_MM = 50;
    // ---------------------------------------------------------------

    // FUNCTION | Collect Per-Mullion Offset Slider Values From a Config
    // ---------------------------------------------------------------
    // Keys are `mullion_offset_1_mm` .. `mullion_offset_6_mm`; the returned
    // array is 0-indexed so offsets[m - 1] pairs with mullion m.
    //
    // Note the gate differs from Na__GlazebarMath.na_collectBarOffsets,
    // deliberately. The glaze bar pool predates its own toggle, so an
    // ABSENT key there means "pre-toggle config, keep the nudges live".
    // The mullion pool shipped WITH its toggle, so no config can carry
    // mullion nudges without it - an absent key is simply a window saved
    // before V1.6.0, and those must render exactly as they always did.
    function na_collectMullionOffsets(config, count) {
        const offsets = [];
        if (!config || !count || count <= 0) return offsets;
        if (config.mullion_offsets_enabled !== true) return offsets;
        for (let i = 1; i <= count; i += 1) {
            const raw = Number(config['mullion_offset_' + i + '_mm']);
            offsets.push(isNaN(raw) ? 0 : raw);
        }
        return offsets;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Equal-Lights Layout (the pre-V1.6.0 behaviour)
    // ---------------------------------------------------------------
    function na_computeEvenMullionLayout(innerLeft, innerWidth, count, mullionWidth) {
        const openingWidth = (innerWidth - (count * mullionWidth)) / (count + 1);
        const mullions = [];
        const openings = [];

        for (let openingIndex = 0; openingIndex <= count; openingIndex += 1) {
            openings.push({
                index : openingIndex,
                x     : innerLeft + (openingIndex * (openingWidth + mullionWidth)),
                width : openingWidth
            });
        }
        for (let m = 1; m <= count; m += 1) {
            mullions.push({
                index : m,
                x     : innerLeft + (m * openingWidth) + ((m - 1) * mullionWidth),
                width : mullionWidth
            });
        }

        return { mullions: mullions, openings: openings };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Mullion + Opening Positions With Per-Mullion Offsets
    // ---------------------------------------------------------------
    // Walks the mullions left to right, clamping each one against the
    // mullion before it and against the room the mullions after it still
    // need. Because the walk is sequential, mullions can never cross or
    // reorder however the sliders are dragged - the worst a slider can do
    // is push its mullion up against its neighbour's minimum gap.
    //
    // When the frame is too narrow to hold `count` mullions plus their
    // minimum lights at all, the offsets are dropped and the equal-lights
    // layout is returned. That is the same degenerate output the tool
    // produced before this feature, and the validator is already the thing
    // that tells the user the window is too narrow.
    function na_computeMullionLayout(innerLeft, innerWidth, count, mullionWidth, offsetsMm) {
        const safeCount = Math.max(0, Math.round(Number(count) || 0));
        const safeWidth = Math.max(0, Number(mullionWidth) || 0);
        const start     = Number(innerLeft)  || 0;
        const span      = Number(innerWidth) || 0;

        const evenLayout = na_computeEvenMullionLayout(start, span, safeCount, safeWidth);
        if (safeCount === 0) return evenLayout;
        if (!Array.isArray(offsetsMm) || offsetsMm.length === 0) return evenLayout;

        const requiredSpan = (safeCount * safeWidth) + ((safeCount + 1) * NA_MULLION_MIN_OPENING_MM);
        if (span < requiredSpan) return evenLayout;                       // <-- Nothing to distribute; fall back to legacy output

        const innerRight = start + span;
        const mullions   = [];
        let cursor       = start;                                         // <-- Right edge of the previous mullion (or the frame's inner left)

        for (let m = 1; m <= safeCount; m += 1) {
            const offset = Number(offsetsMm[m - 1]);
            const nominal = evenLayout.mullions[m - 1].x + (isNaN(offset) ? 0 : offset);

            const remaining = safeCount - m;                              // <-- Mullions still to place after this one
            const minX = cursor + NA_MULLION_MIN_OPENING_MM;
            const maxX = innerRight
                       - safeWidth
                       - NA_MULLION_MIN_OPENING_MM
                       - (remaining * (safeWidth + NA_MULLION_MIN_OPENING_MM));

            const x = Math.min(Math.max(nominal, minX), maxX);
            mullions.push({ index: m, x: x, width: safeWidth });
            cursor = x + safeWidth;
        }

        const openings = [];
        let openingStart = start;
        mullions.forEach(function (mullion, mullionIndex) {
            openings.push({
                index : mullionIndex,
                x     : openingStart,
                width : Math.max(0, mullion.x - openingStart)
            });
            openingStart = mullion.x + mullion.width;
        });
        openings.push({
            index : safeCount,
            x     : openingStart,
            width : Math.max(0, innerRight - openingStart)
        });

        return { mullions: mullions, openings: openings };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve the Layout Straight From a Flat Config Object
    // ---------------------------------------------------------------
    // Convenience wrapper for the 2D / DXF producers, which all hold the
    // same flat config and the same four frame numbers. Keeps the key
    // names and the clamping in one place rather than at each call site.
    function na_resolveMullionLayoutFromConfig(config, innerLeft, innerWidth) {
        const count        = Math.max(0, Math.round(Number((config && config.mullions) || 0)));
        const mullionWidth = (config && config.mullion_width_mm) || 40;
        const offsets      = na_collectMullionOffsets(config, count);
        return na_computeMullionLayout(innerLeft, innerWidth, count, mullionWidth, offsets);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Narrowest Light in a Resolved Layout
    // ---------------------------------------------------------------
    // The validator used to test one shared opening width. With unequal
    // lights it has to test the smallest one, which is what this returns.
    function na_minimumOpeningWidth(layout) {
        if (!layout || !Array.isArray(layout.openings) || layout.openings.length === 0) return 0;
        return layout.openings.reduce(function (smallest, opening) {
            return Math.min(smallest, opening.width);
        }, Infinity);
    }
    // ---------------------------------------------------------------

    return {
        NA_MULLION_MIN_OPENING_MM        : NA_MULLION_MIN_OPENING_MM,
        na_collectMullionOffsets         : na_collectMullionOffsets,
        na_computeEvenMullionLayout      : na_computeEvenMullionLayout,
        na_computeMullionLayout          : na_computeMullionLayout,
        na_resolveMullionLayoutFromConfig: na_resolveMullionLayoutFromConfig,
        na_minimumOpeningWidth           : na_minimumOpeningWidth
    };
})();

window.Na__MullionMath = Na__MullionMath;
console.log('[NA_MULLION_MATH] Shared mullion layout module loaded');

/* =============================================================================
   END OF FILE
   ============================================================================= */
