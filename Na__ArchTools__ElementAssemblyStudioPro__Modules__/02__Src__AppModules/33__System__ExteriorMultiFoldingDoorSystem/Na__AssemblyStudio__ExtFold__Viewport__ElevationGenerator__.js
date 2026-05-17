/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - BIFOLD DOOR ELEVATION SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtFold__Viewport__ElevationGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Renders a 2D elevation SVG of the bifold-door for the
                live preview viewport in the Windows tab. Shows N panels,
                outer frame, glazing, hinge dots, fold-pattern indicator
                arrows, dimensions, and handle placement on the leading
                slave panel(s). Drawn in millimetre coordinate space using
                bottom-left origin convention so the existing
                Na__Viewport__Controls.na_windowResetFitter padding works
                directly.
   CREATED    : 17-May-2026

   DESCRIPTION:
   - Reads bifold_door_* keys from the unified WindowSystem config.
   - Returns inner-SVG markup string suitable for assignment to
     svgEl.innerHTML, matching Na__Viewport__SvgGenerator.na_generateWindowSvg
     conventions exactly.
   - Coordinate convention: x in mm from left jamb, y in mm from base; the
     na_svgRect helper flips Y for SVG screen-space (origin top-left becomes
     (0, -y - h)). This matches the WindowSystem generator so the shared
     fitter and pan/zoom controls Just Work.
   - Three layout algorithms supported:
       * EqualEqual    - half panels fold left, half fold right
       * AllOneWay     - every panel folds to the same side
       * MasterSlaves  - one swing-only master + remaining slaves on opposite
   - The leading slave panel (the panel furthest from the master jamb) is
     marked with a small handle dot.

   DEPENDENCIES:
   - window.Na__Viewport__SvgGenerator.na_svgRect, na_svgDimensions,
     na_getMaterialColor (reused for visual consistency).
   - window.Na_Viewport.na_render() in WindowSystem MainUiLogic dispatches
     here when config.multifold_mode === true.

   ============================================================================= */


// =============================================================================
// REGION | Bifold Elevation SVG Generator Module
// =============================================================================

const Na__ExtFold__ElevationGenerator = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | Constants
    // -----------------------------------------------------------------------------

    const HINGE_DOT_RADIUS_MM            = 18;             // <-- Hinge marker radius
    const HANDLE_DOT_RADIUS_MM           = 22;             // <-- Handle marker radius
    const HANDLE_DEFAULT_HEIGHT_MM       = 1050;           // <-- Standard handle centre height
    const PANEL_GAP_MM                   = 4;              // <-- Visual gap between adjacent panels
    const FOLD_ARROW_OFFSET_FROM_TOP_MM  = 220;            // <-- Y offset from head down for fold arrows
    const FOLD_ARROW_LEN_MM              = 240;            // <-- Length of fold direction arrow
    const STROKE_BLACK                   = '#1A1A1A';      // <-- Frame and outline stroke
    const STROKE_LIGHT                   = '#5A6470';      // <-- Hinge / handle / arrow stroke
    const FILL_HINGE                     = '#22303C';      // <-- Hinge dot fill
    const FILL_HANDLE                    = '#B8392A';      // <-- Handle dot fill (red, easy to spot)
    const FILL_GLAZING                   = '#D8E8F2';      // <-- Glazing pane fill (pale blue)
    const FILL_FOLD_ARROW                = '#5A6470';      // <-- Fold-direction arrow stroke

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Configuration Resolution
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve a Sanitised Layout Hash from Raw Config
    // ------------------------------------------------------------
    // Reads bifold_door_* keys, applies defaults, validates ranges and
    // returns a pure-data layout descriptor consumed by every drawer.
    function na_resolve_layout(config) {
        const openingWidth   = Math.max(800,  Number(config.bifold_door_opening_width_mm)  || 3600);
        const openingHeight  = Math.max(1500, Number(config.bifold_door_opening_height_mm) || 2100);
        const panelCount     = Math.max(2,    Math.min(8, Math.round(Number(config.bifold_door_panel_count) || 4)));
        const headRail       = Math.max(40,   Number(config.bifold_door_head_rail_mm)  || 95);
        const baseRail       = Math.max(80,   Number(config.bifold_door_base_rail_mm)  || 200);
        const stileWidth     = Math.max(40,   Number(config.bifold_door_stile_width_mm) || 95);
        const layout         = String(config.bifold_door_layout      || 'EqualEqual');
        const openSide       = String(config.bifold_door_open_side   || 'Right');
        const masterSide     = String(config.bifold_door_master_side || 'Right');
        const isGlazed       = config.bifold_door_glazed !== false;
        const showDimensions = config.show_dimensions    !== false;

        const frameMaterialId = config.frame_material_id || 'MAT120__GenericWood';
        const frameColour     = na_safe_material_colour(frameMaterialId);

        const panelClearWidth = (openingWidth - 2 * stileWidth) / panelCount;       // <-- Width of each panel including its own stiles
        const panelClearHeight = openingHeight;                                     // <-- Full height (head + base rail are inside panels for bifold)

        return {
            openingWidth         : openingWidth,
            openingHeight        : openingHeight,
            panelCount           : panelCount,
            headRail             : headRail,
            baseRail             : baseRail,
            stileWidth           : stileWidth,
            layout               : layout,
            openSide             : openSide,
            masterSide           : masterSide,
            isGlazed             : isGlazed,
            showDimensions       : showDimensions,
            frameColour          : frameColour,
            panelClearWidth      : panelClearWidth,
            panelClearHeight     : panelClearHeight
        };
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Resolve Frame Material Colour With Fallback
    // ------------------------------------------------------------
    function na_safe_material_colour(materialId) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (sg && typeof sg.na_getMaterialColor === 'function') {
            return sg.na_getMaterialColor(materialId);
        }
        return '#FFFFFF';
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Layout Algorithm Resolver
    // -----------------------------------------------------------------------------

    // FUNCTION | Compute Per-Panel Fold Direction Hints
    // ------------------------------------------------------------
    // Returns an array of length `panelCount` where each entry is one of:
    //   'L' - panel folds to the left when opening
    //   'R' - panel folds to the right when opening
    //   'M' - master swing panel (no fold, swings on outer hinge only)
    function na_resolve_fold_directions(layout) {
        const N = layout.panelCount;
        const directions = new Array(N).fill('L');

        if (layout.layout === 'EqualEqual') {
            const halfRight = Math.floor(N / 2);
            const halfLeft  = N - halfRight;
            for (let i = 0; i < halfLeft;  i++) directions[i]              = 'L';
            for (let i = 0; i < halfRight; i++) directions[halfLeft + i]   = 'R';
            return directions;
        }

        if (layout.layout === 'AllOneWay') {
            const dir = (layout.openSide === 'Left') ? 'L' : 'R';
            for (let i = 0; i < N; i++) directions[i] = dir;
            return directions;
        }

        if (layout.layout === 'MasterSlaves') {
            const masterIsRight = layout.masterSide === 'Right';
            if (masterIsRight) {
                directions[N - 1] = 'M';                                    // <-- Right-most panel is master
                for (let i = 0; i < N - 1; i++) directions[i] = 'L';        // <-- Slaves fold to the left
            } else {
                directions[0] = 'M';                                        // <-- Left-most panel is master
                for (let i = 1; i < N; i++) directions[i] = 'R';            // <-- Slaves fold to the right
            }
            return directions;
        }

        return directions;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Outer Frame Drawing
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for the Outer Bifold Frame (Head + Base + Stiles)
    // ------------------------------------------------------------
    function na_build_outer_frame(layout) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg || typeof sg.na_svgRect !== 'function') return '';

        const { openingWidth, openingHeight, frameColour } = layout;
        let svg = '';

        svg += sg.na_svgRect(0, 0,
            openingWidth, layout.baseRail,
            frameColour, STROKE_BLACK, 1
        );
        svg += sg.na_svgRect(0, openingHeight - layout.headRail,
            openingWidth, layout.headRail,
            frameColour, STROKE_BLACK, 1
        );
        svg += sg.na_svgRect(0, layout.baseRail,
            layout.stileWidth, openingHeight - layout.headRail - layout.baseRail,
            frameColour, STROKE_BLACK, 1
        );
        svg += sg.na_svgRect(openingWidth - layout.stileWidth, layout.baseRail,
            layout.stileWidth, openingHeight - layout.headRail - layout.baseRail,
            frameColour, STROKE_BLACK, 1
        );

        return svg;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Per-Panel Drawing (Stiles, Rails, Glazing)
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for All Bifold Panels Inside the Frame
    // ------------------------------------------------------------
    function na_build_all_panels(layout) {
        const innerLeft   = layout.stileWidth;
        const innerBottom = layout.baseRail;
        const innerWidth  = layout.openingWidth - 2 * layout.stileWidth;
        const innerHeight = layout.openingHeight - layout.headRail - layout.baseRail;
        const panelStep   = innerWidth / layout.panelCount;

        let svg = '';
        for (let i = 0; i < layout.panelCount; i++) {
            const px = innerLeft + i * panelStep + (PANEL_GAP_MM / 2);
            const py = innerBottom;
            const pw = panelStep - PANEL_GAP_MM;
            const ph = innerHeight;
            svg += na_build_one_panel(px, py, pw, ph, layout, i);
        }
        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Build SVG for a Single Bifold Panel
    // ------------------------------------------------------------
    // Each panel = 4 sub-rails (top + bottom + left stile + right stile) +
    // optional glazing rectangle in the centre. We use the bifold-level
    // headRail/baseRail/stileWidth so panels share the parent frame style.
    function na_build_one_panel(panelX, panelY, panelWidth, panelHeight, layout, panelIndex) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) return '';

        const colour    = layout.frameColour;
        const headRail  = Math.min(layout.headRail, panelHeight * 0.25);
        const baseRail  = Math.min(layout.baseRail, panelHeight * 0.35);
        const stile     = Math.min(layout.stileWidth, panelWidth * 0.30);

        let svg = '';

        const glazedX  = panelX + stile;
        const glazedY  = panelY + baseRail;
        const glazedW  = Math.max(0, panelWidth  - 2 * stile);
        const glazedH  = Math.max(0, panelHeight - baseRail - headRail);
        if (layout.isGlazed && glazedW > 0 && glazedH > 0) {
            svg += sg.na_svgRect(glazedX, glazedY, glazedW, glazedH, FILL_GLAZING, STROKE_BLACK, 1);
        } else if (glazedW > 0 && glazedH > 0) {
            svg += sg.na_svgRect(glazedX, glazedY, glazedW, glazedH, colour, STROKE_BLACK, 1);
        }

        svg += sg.na_svgRect(panelX, panelY, stile, panelHeight, colour, STROKE_BLACK, 1);
        svg += sg.na_svgRect(panelX + panelWidth - stile, panelY, stile, panelHeight, colour, STROKE_BLACK, 1);
        svg += sg.na_svgRect(panelX, panelY, panelWidth, baseRail, colour, STROKE_BLACK, 1);
        svg += sg.na_svgRect(panelX, panelY + panelHeight - headRail, panelWidth, headRail, colour, STROKE_BLACK, 1);

        return svg;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Hinge Dot & Fold Arrow Indicators
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for All Hinge Dots
    // ------------------------------------------------------------
    // For each panel-to-panel boundary we draw two hinge dots (top + bottom).
    // For panels hinged to the wall jamb we draw additional dots at the
    // outer edges of the first/last panel based on fold direction.
    function na_build_hinge_dots(layout, foldDirections) {
        const innerLeft   = layout.stileWidth;
        const innerBottom = layout.baseRail;
        const innerWidth  = layout.openingWidth - 2 * layout.stileWidth;
        const innerHeight = layout.openingHeight - layout.headRail - layout.baseRail;
        const panelStep   = innerWidth / layout.panelCount;
        const topY        = innerBottom + innerHeight - 100;
        const botY        = innerBottom + 100;

        let svg = '';

        for (let i = 1; i < layout.panelCount; i++) {
            const x = innerLeft + i * panelStep;
            svg += na_build_one_dot(x, topY, HINGE_DOT_RADIUS_MM, FILL_HINGE, STROKE_LIGHT);
            svg += na_build_one_dot(x, botY, HINGE_DOT_RADIUS_MM, FILL_HINGE, STROKE_LIGHT);
        }

        const firstDir = foldDirections[0];
        if (firstDir === 'L' || firstDir === 'M') {
            svg += na_build_one_dot(innerLeft, topY, HINGE_DOT_RADIUS_MM, FILL_HINGE, STROKE_LIGHT);
            svg += na_build_one_dot(innerLeft, botY, HINGE_DOT_RADIUS_MM, FILL_HINGE, STROKE_LIGHT);
        }
        const lastDir = foldDirections[layout.panelCount - 1];
        if (lastDir === 'R' || lastDir === 'M') {
            const x = innerLeft + innerWidth;
            svg += na_build_one_dot(x, topY, HINGE_DOT_RADIUS_MM, FILL_HINGE, STROKE_LIGHT);
            svg += na_build_one_dot(x, botY, HINGE_DOT_RADIUS_MM, FILL_HINGE, STROKE_LIGHT);
        }

        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Build a Filled Circle (Y-Flipped for SVG)
    // ------------------------------------------------------------
    function na_build_one_dot(x, y, radius, fill, stroke) {
        const svgY = -y;
        return `<circle cx="${x}" cy="${svgY}" r="${radius}" fill="${fill}" stroke="${stroke}" stroke-width="1.5"/>`;
    }
    // ---------------------------------------------------------------


    // FUNCTION | Build SVG for Per-Panel Fold Direction Arrows
    // ------------------------------------------------------------
    // A small horizontal arrow at the top of each panel showing its fold
    // direction. Master panels show a dot+circle "swing" glyph instead.
    function na_build_fold_arrows(layout, foldDirections) {
        const innerLeft   = layout.stileWidth;
        const innerBottom = layout.baseRail;
        const innerWidth  = layout.openingWidth - 2 * layout.stileWidth;
        const innerHeight = layout.openingHeight - layout.headRail - layout.baseRail;
        const panelStep   = innerWidth / layout.panelCount;
        const arrowY      = innerBottom + innerHeight - FOLD_ARROW_OFFSET_FROM_TOP_MM;

        let svg = '';
        for (let i = 0; i < layout.panelCount; i++) {
            const cx = innerLeft + (i + 0.5) * panelStep;
            const dir = foldDirections[i];
            if (dir === 'M') {
                svg += na_build_master_swing_glyph(cx, arrowY);
            } else {
                const sign = (dir === 'L') ? -1 : +1;
                svg += na_build_arrow_horizontal(cx, arrowY, FOLD_ARROW_LEN_MM, sign);
            }
        }
        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Build a Horizontal Arrow Centred on (cx, cy)
    // ------------------------------------------------------------
    function na_build_arrow_horizontal(cx, cy, length, sign) {
        const half  = length / 2;
        const x1    = cx - sign * half;
        const x2    = cx + sign * half;
        const svgY  = -cy;
        const head  = 50 * sign;
        const tipY1 = svgY - 30;
        const tipY2 = svgY + 30;
        return [
            `<line x1="${x1}" y1="${svgY}" x2="${x2}" y2="${svgY}" stroke="${FILL_FOLD_ARROW}" stroke-width="6" stroke-linecap="round"/>`,
            `<line x1="${x2 - head}" y1="${tipY1}" x2="${x2}" y2="${svgY}" stroke="${FILL_FOLD_ARROW}" stroke-width="6" stroke-linecap="round"/>`,
            `<line x1="${x2 - head}" y1="${tipY2}" x2="${x2}" y2="${svgY}" stroke="${FILL_FOLD_ARROW}" stroke-width="6" stroke-linecap="round"/>`
        ].join('');
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Build a Master-Swing "Open Door" Glyph
    // ------------------------------------------------------------
    function na_build_master_swing_glyph(cx, cy) {
        const svgY = -cy;
        const r    = FOLD_ARROW_LEN_MM * 0.45;
        return [
            `<path d="M ${cx - r} ${svgY} A ${r} ${r} 0 0 1 ${cx + r} ${svgY}" `,
            `      fill="none" stroke="${FILL_FOLD_ARROW}" stroke-width="6" stroke-dasharray="14,10"/>`,
            `<circle cx="${cx}" cy="${svgY + r}" r="14" fill="${FILL_FOLD_ARROW}"/>`
        ].join('');
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Handle Marker
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for the Handle Dot on the Lead Slave Panel
    // ------------------------------------------------------------
    // Handle goes on the panel that the user grabs to start opening - this is
    // the panel adjacent to the master (or adjacent to the wall on the open
    // side for All-One-Way / Equal-Equal).
    function na_build_handle_dot(layout, foldDirections) {
        const innerLeft   = layout.stileWidth;
        const innerWidth  = layout.openingWidth - 2 * layout.stileWidth;
        const panelStep   = innerWidth / layout.panelCount;

        const handleIndex = na_resolve_handle_panel_index(layout, foldDirections);
        if (handleIndex < 0) return '';

        const dir = foldDirections[handleIndex];
        const sign = (dir === 'L') ? -1 : +1;
        const cx = innerLeft + (handleIndex + 0.5) * panelStep + sign * (panelStep * 0.4);
        const cy = HANDLE_DEFAULT_HEIGHT_MM;

        return na_build_one_dot(cx, cy, HANDLE_DOT_RADIUS_MM, FILL_HANDLE, STROKE_BLACK);
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Resolve Which Panel Carries the Handle
    // ------------------------------------------------------------
    function na_resolve_handle_panel_index(layout, foldDirections) {
        if (layout.layout === 'MasterSlaves') {
            return foldDirections.indexOf('M');
        }
        if (layout.layout === 'AllOneWay') {
            return (layout.openSide === 'Right') ? layout.panelCount - 1 : 0;
        }
        if (layout.layout === 'EqualEqual') {
            return Math.floor(layout.panelCount / 2);
        }
        return -1;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Public API - Compose the Full Bifold Elevation
    // -----------------------------------------------------------------------------

    // FUNCTION | Generate Full SVG Markup for the Bifold Elevation
    // ------------------------------------------------------------
    // @param  {Object} config - WindowSystem unified config (incl. bifold_door_*)
    // @return {string}        - Inner-SVG markup ready for assignment to innerHTML
    function na_generate_bifold_svg(config) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) {
            console.warn('[NA_EXT_FOLD_SVG] Na__Viewport__SvgGenerator missing');
            return '';
        }

        const layout         = na_resolve_layout(config);
        const foldDirections = na_resolve_fold_directions(layout);

        let svg = '';
        svg += na_build_outer_frame(layout);
        svg += na_build_all_panels(layout);
        svg += na_build_hinge_dots(layout, foldDirections);
        svg += na_build_fold_arrows(layout, foldDirections);
        svg += na_build_handle_dot(layout, foldDirections);

        if (layout.showDimensions && typeof sg.na_svgDimensions === 'function') {
            svg += sg.na_svgDimensions(layout.openingWidth, layout.openingHeight);
        }

        return svg;
    }
    // ---------------------------------------------------------------


    // FUNCTION | Legacy Phase-1 API - Returns Wrapped SVG Document
    // ------------------------------------------------------------
    // Kept for any caller still expecting the standalone SVG string. Prefer
    // na_generate_bifold_svg(config) inside the WindowSystem viewport.
    function na_render_elevation_svg(config_hash, viewport_box) {
        const innerSvg = na_generate_bifold_svg(config_hash || {});
        const w = (viewport_box && viewport_box.width)  || 800;
        const h = (viewport_box && viewport_box.height) || 600;
        return [
            '<svg xmlns="http://www.w3.org/2000/svg" width="', w, '" height="', h, '" viewBox="0 0 ', w, ' ', h, '">',
                innerSvg,
            '</svg>'
        ].join('');
    }
    // ---------------------------------------------------------------


    return {
        na_generate_bifold_svg     : na_generate_bifold_svg,
        na_render_elevation_svg    : na_render_elevation_svg,
        na_resolve_layout          : na_resolve_layout,
        na_resolve_fold_directions : na_resolve_fold_directions
    };

    // endregion -------------------------------------------------------------------

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtFold__ElevationGenerator = Na__ExtFold__ElevationGenerator;

console.log('[NA_EXT_FOLD] Bifold Elevation SVG Generator loaded');

// endregion -------------------------------------------------------------------
