/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - ARCH MATH (ARCHED HEADER RAILS)
   =============================================================================
   FILE       : Na__AssemblyStudio__WindowSystem__Viewport__ArchMath__.js
   NAMESPACE  : window.Na__ArchMath
   AUTHOR     : Noble Architecture
   PURPOSE    : The arc of an arched header rail and the outlines it makes, for
                the window and door previews, the JS DXF exporters and the UI.
                Mirrored in Ruby by Na__ArchedHeaderBuilder, which builds the
                solids from the same sums.
   CREATED    : 03-Nov-2026

   THE RULE
   - The top of the rail stays flat and the glass takes the arched head. The
     crown of the arc sits where the flat glass top was, so the rail keeps its
     set depth at the centre. The arc falls away from there by the Arch Height,
     and the rail deepens towards the stiles to fill the corners.
   - A segmental arc (a rise under half the glass width) keeps the joinery rule:
     stiles full height, the rail between them.
   - A true arch (a rise of half the glass width, a semicircle) makes a special
     head rail: one piece across the full width, on stiles that stop at the
     springing line, because a rail between the stiles would end in a long
     feather edge.
   - An arch never takes the glass below its least side height, so a short pane
     gets the tallest segmental arc that fits it.

   PUBLIC API
   - na_settings(config, prefix)            { riseMm, trueArch, segments } or null
   - na_resolve(settings, x, z, width, height)
                                            The arch over one glass rectangle, or null
   - na_topOver(arch, leftX, rightX)        Highest point of the arc over a span
   - na_trimHeight(arch, leftX, rightX, startZ, height)
                                            Height of a vertical member under it
   - na_trimRun(arch, startX, width, bottomZ)
                                            [startX, width] of a horizontal one
   - na_stileHeight(arch, bottomZ, height)  Height of the stiles under the head
   - na_headOutline(arch, outerLeft, outerRight, topZ)
                                            Rail outline, [x, z] pairs
   - na_glassOutline(arch, bottomZ)         Glass outline, [x, z] pairs
   - na_sliderMaxMm(widestSpanMm)           Where the height slider tops out

   ============================================================================= */

const Na__ArchMath = (function () {

    const NA_MIN_RISE_MM       = 20;                                            // <-- The slider's floor
    const NA_DEFAULT_RISE_MM   = 60;                                            // <-- A slight segmental arc
    const NA_SEGMENT_CHOICES   = [12, 24, 48];
    const NA_MIN_SIDE_MM       = 20;                                            // <-- Glass kept at each side, under the springing line
    const NA_MIN_LIMIT_MM      = 1;                                             // <-- Less room than this: no arch at all
    const NA_TRUE_TOLERANCE_MM = 0.5;                                           // <-- This close to half the width reads as a true arch
    const NA_SLIDER_STEP_MM    = 5;

    // FUNCTION | Read the Arched Header Settings From a Config
    // ---------------------------------------------------------------
    // An absent switch reads as off, so every element saved before the feature
    // existed draws as it was.
    // @param {Object} config - Window or door configuration
    // @param {string} prefix - '' for windows, 'single_door_' and so on for doors
    // @returns {Object|null}   { riseMm, trueArch, segments }, null when off
    function na_settings(config, prefix) {
        const keyPrefix = prefix || '';
        if (!config || config[keyPrefix + 'arched_header_enabled'] !== true) return null;

        const height = config[keyPrefix + 'arched_header_height_mm'];
        const segments = Number(config[keyPrefix + 'arched_header_segments']);
        return {
            riseMm   : Math.max(Number(height == null ? NA_DEFAULT_RISE_MM : height) || NA_DEFAULT_RISE_MM, NA_MIN_RISE_MM),
            trueArch : config[keyPrefix + 'arched_header_true_arch'] === true,
            segments : NA_SEGMENT_CHOICES.indexOf(segments) !== -1 ? segments : NA_SEGMENT_CHOICES[0]
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve the Arch Over One Glass Rectangle
    // ---------------------------------------------------------------
    // x, z, width, height are the glass as if it were flat, in millimetres.
    // @returns {Object|null} Null when there is no room for an arch
    function na_resolve(settings, x, z, width, height) {
        if (!settings || !(width > 0) || !(height > 0)) return null;

        const half = width / 2;
        const limit = Math.min(half, height - NA_MIN_SIDE_MM);
        if (!(limit >= NA_MIN_LIMIT_MM)) return null;

        const wanted = settings.trueArch ? half : settings.riseMm;
        const rise = Math.min(wanted, limit);
        const radius = ((half * half) + (rise * rise)) / (2 * rise);
        const crownZ = z + height;

        const arch = {
            left       : x,
            right      : x + width,
            crownZ     : crownZ,
            springingZ : crownZ - rise,
            rise       : rise,
            radius     : radius,
            centreX    : x + half,
            centreZ    : crownZ - radius,
            segments   : settings.segments,
            trueArch   : rise >= half - NA_TRUE_TOLERANCE_MM
        };
        arch.points = na_arcPoints(arch);
        return arch;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Tessellate the Arc, Left Springing to Right Springing
    // ---------------------------------------------------------------
    // The segment count is even, so one point is the crown itself and the
    // rail's retained depth is exact.
    function na_arcPoints(arch) {
        const half = (arch.right - arch.left) / 2;
        const halfAngle = Math.atan2(half, arch.radius - arch.rise);
        const points = [];
        for (let index = 0; index <= arch.segments; index += 1) {
            const angle = halfAngle * ((2 * index / arch.segments) - 1);
            points.push([arch.centreX + (arch.radius * Math.sin(angle)), arch.centreZ + (arch.radius * Math.cos(angle))]);
        }
        points[0] = [arch.left, arch.springingZ];
        points[points.length - 1] = [arch.right, arch.springingZ];
        return points;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Highest Point of the Arc Over a Span of X
    // ---------------------------------------------------------------
    // Measured on the true circle, which is never below the facets, so a bar
    // stopped here runs just into the rail and leaves no gap.
    function na_topOver(arch, leftX, rightX) {
        let nearest = 0;
        if (leftX > arch.centreX) nearest = leftX - arch.centreX;
        else if (rightX < arch.centreX) nearest = arch.centreX - rightX;
        if (nearest >= (arch.right - arch.left) / 2) return arch.springingZ;
        return arch.centreZ + Math.sqrt(Math.max((arch.radius * arch.radius) - (nearest * nearest), 0));
    }
    // ---------------------------------------------------------------

    // FUNCTION | Height of a Vertical Member Under the Arch
    // ---------------------------------------------------------------
    // @returns {number|null} The member's height, null when the arch leaves none
    function na_trimHeight(arch, leftX, rightX, startZ, height) {
        if (!arch) return height;
        const trimmed = Math.min(na_topOver(arch, leftX, rightX) - startZ, height);
        return trimmed > 0 ? trimmed : null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Run of a Horizontal Member Under the Arch
    // ---------------------------------------------------------------
    // bottomZ is the member's underside, where the arch is widest, so its ends
    // run just into the rail.
    // @returns {Array|null} [startX, width], null when it lies above the arch
    function na_trimRun(arch, startX, width, bottomZ) {
        if (!arch || bottomZ <= arch.springingZ) return [startX, width];
        if (bottomZ >= arch.crownZ) return null;

        const drop = bottomZ - arch.centreZ;
        const halfRun = Math.sqrt(Math.max((arch.radius * arch.radius) - (drop * drop), 0));
        const left = Math.max(startX, arch.centreX - halfRun);
        const right = Math.min(startX + width, arch.centreX + halfRun);
        return right > left ? [left, right - left] : null;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Height of the Stiles Under the Head
    // ---------------------------------------------------------------
    // A true arch's head rail sits on the stiles. A segmental rail fits between
    // them, so they stay full height.
    function na_stileHeight(arch, bottomZ, fullHeight) {
        return (arch && arch.trueArch) ? arch.springingZ - bottomZ : fullHeight;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Outline of the Header Rail
    // ---------------------------------------------------------------
    // Clockwise from the top left, seen from outside. The flat top, then the
    // arc back from right to left. A true arch's special head runs out over
    // the stiles along the springing line.
    function na_headOutline(arch, outerLeft, outerRight, topZ) {
        const reversed = arch.points.slice().reverse();
        if (!arch.trueArch) return [[arch.left, topZ], [arch.right, topZ]].concat(reversed);
        return [[outerLeft, topZ], [outerRight, topZ], [outerRight, arch.springingZ]]
            .concat(reversed)
            .concat([[outerLeft, arch.springingZ]]);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Outline of the Glass
    // ---------------------------------------------------------------
    function na_glassOutline(arch, bottomZ) {
        return [[arch.left, bottomZ], [arch.right, bottomZ]].concat(arch.points.slice().reverse());
    }
    // ---------------------------------------------------------------

    // FUNCTION | Where the Arch Height Slider Tops Out
    // ---------------------------------------------------------------
    // A true arch over the widest glass in the element. Rounded up to the
    // slider's step, so its last stop always reaches it; a narrower casement
    // reaches its own true arch sooner.
    function na_sliderMaxMm(widestSpanMm) {
        const half = Math.max(0, Number(widestSpanMm) || 0) / 2;
        return Math.max(NA_MIN_RISE_MM, Math.ceil(half / NA_SLIDER_STEP_MM) * NA_SLIDER_STEP_MM);
    }
    // ---------------------------------------------------------------

    return {
        na_settings     : na_settings,
        na_resolve      : na_resolve,
        na_topOver      : na_topOver,
        na_trimHeight   : na_trimHeight,
        na_trimRun      : na_trimRun,
        na_stileHeight  : na_stileHeight,
        na_headOutline  : na_headOutline,
        na_glassOutline : na_glassOutline,
        na_sliderMaxMm  : na_sliderMaxMm
    };
})();

window.Na__ArchMath = Na__ArchMath;
console.log('[NA_ARCH_MATH] Shared arched header math module loaded');

/* =============================================================================
   END OF FILE
   ============================================================================= */
