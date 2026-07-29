/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - GLAZEBAR MATH (SHARED 2D HELPERS)
   =============================================================================
   FILE       : Na__AssemblyStudio__WindowSystem__Viewport__GlazebarMath__.js
   NAMESPACE  : window.Na__GlazebarMath
   AUTHOR     : Noble Architecture
   PURPOSE    : Pure geometry helpers shared between the WindowSystem SVG
                generator and the ExtFold / ExtSlide elevation generators.
                Keeps margin-glazing positioning and Gothic-arch parameters
                in ONE place so all three 2D previews stay in lockstep with
                each other (and with the Ruby 3D side that uses the same
                formulae).

   PUBLIC API
   - na_computeBarPositions(start, size, count, marginEnabled, marginOffset)
       Returns an array of axis-positions for bar centerlines.
       Default mode  : evenly divides `size` into (count+1) sections.
       Margin mode   : (only when count >= 2) places the outer pair inset
                       by `marginOffset` and distributes inner bars evenly.

   - na_computeEffectiveGlassHeight(glassHeight, archEnabled, archHeight)
       Returns the height available for regular glaze bars when the Gothic
       arch zone occupies the top of the glazed area.

   - na_computeGothicArcParams(bayWidth, archHeight)
       Returns the two-centred arc parameters for ONE bay (one arch). The
       caller draws two arcs per bay (left + right) using these centres,
       the shared radius, and the start/end angles that include a 15-degree
       overshoot past the apex.

   - na_gothicTessellationSegmentCount(archHeightMm)
       Returns the per-arc segment count for 3D tessellation.
       Provided here too so SVG / DXF / 3D all agree on segmentation.

   - na_applyBarOffsets(positions, offsets)
       Adds a signed per-bar offset to each bar centerline AFTER the
       spacing step (even / margin / arch-aligned). offsets[i] pairs with
       positions[i]; missing or non-numeric entries mean "no nudge".

   - na_collectBarOffsets(config, prefix, count)
       Gathers the per-bar offset slider values (glazebar_h_offset_N_mm /
       glazebar_v_offset_N_mm, N = 1-based) from a flat config object
       into a 0-indexed numeric array of length `count`.

   - na_computeCellBounds(start, size, barPositions, barWidth)
       Splits one axis of a glass pane into cell segments between glaze
       bar EDGES (centerline +/- barWidth/2). Returns [{start, size}]
       ordered from `start` upward; degenerate segments are clamped to
       size 0 so callers can skip them.

   ============================================================================= */

const Na__GlazebarMath = (function () {

    // FUNCTION | Position bar centerlines along one axis
    // ---------------------------------------------------------------
    function na_computeBarPositions(start, size, count, marginEnabled, marginOffset) {
        if (!count || count <= 0) return [];

        // Margin glazing only kicks in for >= 2 bars; with 0 or 1 bars
        // the concept of an "outer pair" does not apply, so fall back to
        // the standard divide-by-(N+1) algorithm.
        if (!marginEnabled || count < 2) {
            const step = size / (count + 1);
            const positions = [];
            for (let i = 1; i <= count; i += 1) {
                positions.push(start + step * i);
            }
            return positions;
        }

        const safeMargin = Math.max(0, Number(marginOffset) || 0);
        const firstPos = start + safeMargin;
        const lastPos  = start + size - safeMargin;

        if (count === 2) return [firstPos, lastPos];

        const innerStep = (lastPos - firstPos) / (count - 1);
        const positions = [];
        for (let i = 0; i < count; i += 1) {
            positions.push(firstPos + innerStep * i);
        }
        return positions;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Reduce the glazed area's height by the arch zone
    // ---------------------------------------------------------------
    // Two callable shapes:
    //   na_computeEffectiveGlassHeight(glassHeight, archEnabled, archHeight)
    //     - Legacy/simple. Subtracts only the apex height (springing line
    //       lands `archHeight` below top of glass; apex sits AT top of
    //       glass). Kept for callers that have not adopted the total-zone
    //       helper yet.
    //   na_computeEffectiveGlassHeight(glassHeight, archEnabled, archHeight, glassWidth, archAmount)
    //     - Preferred. Subtracts the full arch zone (apex + overshoot)
    //       so the OVERSHOOT TERMINI land at the top of glass and the
    //       apex sits below. Matches the user's architectural intent
    //       where the casement's top rail forms the top boundary of the
    //       arch tracery.
    function na_computeEffectiveGlassHeight(glassHeight, archEnabled, archHeight, glassWidth, archAmount) {
        if (!archEnabled) return glassHeight;
        const h = Math.max(0, Number(archHeight) || 0);
        if (glassWidth == null || archAmount == null) {
            return Math.max(0, glassHeight - h);
        }
        const bayWidth = Number(glassWidth) / Math.max(1, Math.round(archAmount));
        const total = na_computeGothicTotalZoneHeight(bayWidth, h);
        return Math.max(0, glassHeight - total);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Total Visible Arch Zone Height (Apex + Overshoot)
    // ---------------------------------------------------------------
    // The 15-deg overshoot pushes each arc's terminus ABOVE the apex.
    // This helper returns the VISIBLE top of that geometry so the caller
    // can shift the springing line down by the right amount and keep the
    // entire arch tracery inside the casement header.
    function na_computeGothicTotalZoneHeight(bayWidth, apexHeight) {
        const params = na_computeGothicArcParams(bayWidth, apexHeight);
        const terminusY = params.radius * Math.sin(params.leftEndAng);
        return Math.max(apexHeight, terminusY);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Two-centred Gothic arc parameters for one bay
    // ---------------------------------------------------------------
    // For a bay of width W and a user-desired apex height H above the
    // springing line, place each arc's centre at horizontal offset
    //   c = W/4 + H^2 / W
    // from the OPPOSITE springing point (i.e. left arc centre sits at
    // x = c measured from the left springing, with x = 0 being the left
    // springing point and x = W being the right springing point).
    //
    // Radius = c (the arc passes through its own near springing point).
    // The arcs cross at the bay centerline (x = W/2) at height H.
    //
    // Both arcs sweep PAST the apex by `overshootDeg` (15 deg) to produce
    // the visible overshoot characteristic of the reference image.
    //
    // Coordinate convention used by callers: the bay's left springing
    // point is at the origin (0, 0); +x runs along the springing line to
    // the right; +y points up into the arch zone.
    function na_computeGothicArcParams(bayWidth, archHeight) {
        const W = Math.max(0.0001, Number(bayWidth)  || 0);
        const H = Math.max(0.0001, Number(archHeight) || 0);
        const c = (W / 4) + (H * H) / W;
        const R = c;

        // Left arc: centred at (x = c, y = 0). The near springing point
        // (left springing, (0, 0)) corresponds to angle PI.
        // The apex (W/2, H) corresponds to angle = atan2(H, W/2 - c).
        const apexAngleLeft  = Math.atan2(H, (W / 2) - c);
        const overshoot      = (15 * Math.PI) / 180;
        const startAngleLeft = Math.PI;
        const endAngleLeft   = apexAngleLeft - overshoot;

        // Right arc: centred at (x = W - c, y = 0). The near springing
        // point (right springing, (W, 0)) corresponds to angle 0. The
        // apex (W/2, H) corresponds to angle = atan2(H, (W/2) - (W - c)).
        const rightCenterX    = W - c;
        const apexAngleRight  = Math.atan2(H, (W / 2) - rightCenterX);
        const startAngleRight = 0;
        const endAngleRight   = apexAngleRight + overshoot;

        return {
            bayWidth      : W,
            archHeight    : H,
            radius        : R,
            leftCenterX   : c,
            rightCenterX  : rightCenterX,
            leftStartAng  : startAngleLeft,
            leftEndAng    : endAngleLeft,
            rightStartAng : startAngleRight,
            rightEndAng   : endAngleRight,
            apexX         : W / 2,
            apexY         : H
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Arch-Aligned Bar Positions
    // ---------------------------------------------------------------
    // When the Gothic arch tracery is on, the arch springings live at
    // positions within the EXTENDED arch zone (glass + barWidth wider).
    // To make the outermost vertical bars sit directly under the
    // outermost interior springings (so the bar reads as a continuation
    // of the arch's mullion), divide the extended zone into `archAmount`
    // bays and return the interior springing positions.
    //
    // Caller is expected to invoke this only when count === archAmount-1,
    // which is the natural pairing where one vertical bar sits below
    // every interior arch springing.
    function na_computeArchAlignedBarPositions(glassStart, glassSize, count, barWidth, archAmount) {
        if (!count || count <= 0 || !archAmount || archAmount < 2) return [];
        const halfBar       = barWidth / 2;
        const extGlassStart = glassStart - halfBar;
        const extGlassSize  = glassSize + (2 * halfBar);
        const extBayWidth   = extGlassSize / archAmount;
        const positions = [];
        for (let i = 0; i < count; i += 1) {
            positions.push(extGlassStart + (i + 1) * extBayWidth);
        }
        return positions;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Tessellation segment count per arc
    // ---------------------------------------------------------------
    function na_gothicTessellationSegmentCount(archHeightMm) {
        const h = Math.max(0, Number(archHeightMm) || 0);
        if (h < 450) return 24;
        if (h <= 600) return 36;
        return 48;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Apply per-bar offsets after the spacing step
    // ---------------------------------------------------------------
    function na_applyBarOffsets(positions, offsets) {
        if (!Array.isArray(positions) || positions.length === 0) return positions || [];
        if (!Array.isArray(offsets) || offsets.length === 0) return positions;
        return positions.map(function (position, index) {
            const offset = Number(offsets[index]);
            return isNaN(offset) ? position : position + offset;
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Collect per-bar offset slider values from a config
    // ---------------------------------------------------------------
    // prefix is 'glazebar_h_offset_' or 'glazebar_v_offset_'; keys are
    // 1-based ('glazebar_h_offset_1_mm'), the returned array 0-indexed.
    function na_collectBarOffsets(config, prefix, count) {
        const offsets = [];
        if (!config || !count || count <= 0) return offsets;
        for (let i = 1; i <= count; i += 1) {
            const raw = Number(config[prefix + i + '_mm']);
            offsets.push(isNaN(raw) ? 0 : raw);
        }
        return offsets;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Split one axis into cell segments between bar edges
    // ---------------------------------------------------------------
    // barPositions are FINAL centerlines (offsets already applied).
    // Returns (barPositions.length + 1) segments spanning glass edge ->
    // bar edge, bar edge -> bar edge, ..., bar edge -> glass edge.
    function na_computeCellBounds(start, size, barPositions, barWidth) {
        const positions = Array.isArray(barPositions) ? barPositions.slice() : [];
        positions.sort(function (a, b) { return a - b; });
        const halfBar = Math.max(0, Number(barWidth) || 0) / 2;
        const cells = [];
        let cursor = start;
        for (let i = 0; i < positions.length; i += 1) {
            const edge = positions[i] - halfBar;
            cells.push({ start: cursor, size: Math.max(0, edge - cursor) });
            cursor = positions[i] + halfBar;
        }
        cells.push({ start: cursor, size: Math.max(0, (start + size) - cursor) });
        return cells;
    }
    // ---------------------------------------------------------------

    return {
        na_computeBarPositions             : na_computeBarPositions,
        na_computeArchAlignedBarPositions  : na_computeArchAlignedBarPositions,
        na_computeEffectiveGlassHeight     : na_computeEffectiveGlassHeight,
        na_computeGothicArcParams          : na_computeGothicArcParams,
        na_computeGothicTotalZoneHeight    : na_computeGothicTotalZoneHeight,
        na_gothicTessellationSegmentCount  : na_gothicTessellationSegmentCount,
        na_applyBarOffsets                 : na_applyBarOffsets,
        na_collectBarOffsets               : na_collectBarOffsets,
        na_computeCellBounds               : na_computeCellBounds
    };
})();

window.Na__GlazebarMath = Na__GlazebarMath;
console.log('[NA_GLAZEBAR_MATH] Shared glazebar math module loaded');
