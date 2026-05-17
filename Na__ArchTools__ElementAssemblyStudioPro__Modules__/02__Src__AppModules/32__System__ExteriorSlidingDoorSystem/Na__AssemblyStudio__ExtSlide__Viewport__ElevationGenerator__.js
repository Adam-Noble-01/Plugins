/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR ELEVATION SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSlide__Viewport__ElevationGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Renders a 2D elevation SVG of the sliding-door for the
                live preview viewport in the Windows tab. Shows the outer
                opening frame, two leaves (front and rear with the rear
                slightly inset to communicate the wall-depth setback), the
                slide-direction arrow on top, the setback indicator on the
                head, and a handle dot on the moving leaf.
   CREATED    : 17-May-2026

   DESCRIPTION:
   - Reads sliding_door_* keys from the unified WindowSystem config.
   - Returns inner-SVG markup string suitable for assignment to
     svgEl.innerHTML, matching Na__Viewport__SvgGenerator.na_generateWindowSvg
     conventions exactly.
   - Coordinate convention: x in mm from left jamb, y in mm from base; the
     na_svgRect helper flips Y for SVG screen-space (origin top-left becomes
     (0, -y - h)).
   - Two slide modes supported:
       * FrontSlidesLeft  - front panel on the right, slides left to open
       * FrontSlidesRight - front panel on the left, slides right to open
   - Setback is shown by drawing the rear panel with a small horizontal
     inset glyph at the head + base, mirroring the wall-depth offset.

   DEPENDENCIES:
   - window.Na__Viewport__SvgGenerator.na_svgRect, na_svgDimensions,
     na_getMaterialColor (reused for visual consistency).
   - window.Na_Viewport.na_render() in WindowSystem MainUiLogic dispatches
     here when config.sliding_mode === true.

   ============================================================================= */


// =============================================================================
// REGION | Sliding Elevation SVG Generator Module
// =============================================================================

const Na__ExtSlide__ElevationGenerator = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | Constants
    // -----------------------------------------------------------------------------

    const HANDLE_DOT_RADIUS_MM       = 22;             // <-- Handle marker radius
    const HANDLE_DEFAULT_HEIGHT_MM   = 1050;           // <-- Standard handle centre height
    const PANEL_OVERLAP_MM           = 30;             // <-- Visual overlap shown at the meeting stiles
    const SLIDE_ARROW_OFFSET_MM      = 220;            // <-- Y offset from head down for slide arrow
    const SLIDE_ARROW_LEN_MM         = 600;            // <-- Length of slide direction arrow
    const SETBACK_GLYPH_OFFSET_MM    = 80;             // <-- Y offset from head for setback chevron
    const SETBACK_GLYPH_LEN_MM       = 80;             // <-- Setback chevron half-length
    const STROKE_BLACK               = '#1A1A1A';      // <-- Frame and outline stroke
    const STROKE_LIGHT               = '#5A6470';      // <-- Slide arrow / setback chevron stroke
    const FILL_HANDLE                = '#B8392A';      // <-- Handle dot fill (red, easy to spot)
    const FILL_GLAZING_FRONT         = '#D8E8F2';      // <-- Front leaf glazing fill
    const FILL_GLAZING_REAR          = '#B8C8D5';      // <-- Rear leaf glazing fill (slightly darker)

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Configuration Resolution
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve a Sanitised Layout Hash from Raw Config
    // ------------------------------------------------------------
    function na_resolve_layout(config) {
        const openingWidth   = Math.max(800,  Number(config.sliding_door_opening_width_mm)  || 2400);
        const openingHeight  = Math.max(1500, Number(config.sliding_door_opening_height_mm) || 2100);
        const headRail       = Math.max(40,   Number(config.sliding_door_head_rail_mm)  || 95);
        const baseRail       = Math.max(80,   Number(config.sliding_door_base_rail_mm)  || 200);
        const stileWidth     = Math.max(40,   Number(config.sliding_door_stile_width_mm) || 95);
        const rearSetback    = Math.max(20,   Number(config.sliding_door_rear_setback_mm) || 60);
        const slideMode      = String(config.sliding_door_mode || 'FrontSlidesRight');
        const isGlazed       = config.sliding_door_glazed !== false;
        const showDimensions = config.show_dimensions     !== false;

        const frameMaterialId = config.frame_material_id || 'MAT120__GenericWood';
        const frameColour     = na_safe_material_colour(frameMaterialId);

        return {
            openingWidth         : openingWidth,
            openingHeight        : openingHeight,
            headRail             : headRail,
            baseRail             : baseRail,
            stileWidth           : stileWidth,
            rearSetback          : rearSetback,
            slideMode            : slideMode,
            isGlazed             : isGlazed,
            showDimensions       : showDimensions,
            frameColour          : frameColour
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
    // REGION | Outer Frame Drawing
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for the Outer Sliding-Door Frame (Head + Base + Stiles)
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
    // REGION | Per-Leaf Drawing (Front + Rear)
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for the Two Sliding Leaves
    // ------------------------------------------------------------
    // Each leaf is half the inner width with a small visual overlap at the
    // meeting stiles so the user can "see" the order of the panels.
    // The rear leaf is drawn first, then the front leaf draws on top so its
    // outline crosses the rear leaf at the overlap.
    function na_build_leaves(layout) {
        const innerLeft   = layout.stileWidth;
        const innerBottom = layout.baseRail;
        const innerWidth  = layout.openingWidth - 2 * layout.stileWidth;
        const innerHeight = layout.openingHeight - layout.headRail - layout.baseRail;
        const halfWidth   = innerWidth / 2;

        const leafW = halfWidth + (PANEL_OVERLAP_MM / 2);

        const frontIsRight = layout.slideMode === 'FrontSlidesLeft';
        const frontX       = frontIsRight ? innerLeft + halfWidth - (PANEL_OVERLAP_MM / 2) : innerLeft;
        const rearX        = frontIsRight ? innerLeft : innerLeft + halfWidth - (PANEL_OVERLAP_MM / 2);

        let svg = '';
        svg += na_build_one_leaf(rearX, innerBottom, leafW, innerHeight, layout, FILL_GLAZING_REAR, true);
        svg += na_build_one_leaf(frontX, innerBottom, leafW, innerHeight, layout, FILL_GLAZING_FRONT, false);
        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Build SVG for a Single Sliding Leaf
    // ------------------------------------------------------------
    function na_build_one_leaf(leafX, leafY, leafWidth, leafHeight, layout, glazingColour, isRear) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) return '';

        const colour    = layout.frameColour;
        const headRail  = Math.min(layout.headRail, leafHeight * 0.20);
        const baseRail  = Math.min(layout.baseRail, leafHeight * 0.30);
        const stile     = Math.min(layout.stileWidth, leafWidth * 0.18);

        let svg = '';

        const glazedX  = leafX + stile;
        const glazedY  = leafY + baseRail;
        const glazedW  = Math.max(0, leafWidth  - 2 * stile);
        const glazedH  = Math.max(0, leafHeight - baseRail - headRail);
        if (layout.isGlazed && glazedW > 0 && glazedH > 0) {
            svg += sg.na_svgRect(glazedX, glazedY, glazedW, glazedH, glazingColour, STROKE_BLACK, 1);
        } else if (glazedW > 0 && glazedH > 0) {
            const fill = isRear ? '#A8B2BE' : colour;
            svg += sg.na_svgRect(glazedX, glazedY, glazedW, glazedH, fill, STROKE_BLACK, 1);
        }

        svg += sg.na_svgRect(leafX, leafY, stile, leafHeight, colour, STROKE_BLACK, 1);
        svg += sg.na_svgRect(leafX + leafWidth - stile, leafY, stile, leafHeight, colour, STROKE_BLACK, 1);
        svg += sg.na_svgRect(leafX, leafY, leafWidth, baseRail, colour, STROKE_BLACK, 1);
        svg += sg.na_svgRect(leafX, leafY + leafHeight - headRail, leafWidth, headRail, colour, STROKE_BLACK, 1);

        return svg;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Slide Direction Arrow & Setback Indicator
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for the Slide-Direction Arrow on the Head
    // ------------------------------------------------------------
    function na_build_slide_arrow(layout) {
        const innerLeft   = layout.stileWidth;
        const innerBottom = layout.baseRail;
        const innerWidth  = layout.openingWidth - 2 * layout.stileWidth;
        const innerHeight = layout.openingHeight - layout.headRail - layout.baseRail;

        const arrowY = innerBottom + innerHeight - SLIDE_ARROW_OFFSET_MM;
        const cx     = innerLeft + innerWidth / 2;
        const sign   = (layout.slideMode === 'FrontSlidesLeft') ? -1 : +1;

        return na_build_arrow_horizontal(cx, arrowY, SLIDE_ARROW_LEN_MM, sign);
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Build a Horizontal Arrow Centred on (cx, cy)
    // ------------------------------------------------------------
    function na_build_arrow_horizontal(cx, cy, length, sign) {
        const half  = length / 2;
        const x1    = cx - sign * half;
        const x2    = cx + sign * half;
        const svgY  = -cy;
        const head  = 80 * sign;
        const tipY1 = svgY - 40;
        const tipY2 = svgY + 40;
        return [
            `<line x1="${x1}" y1="${svgY}" x2="${x2}" y2="${svgY}" stroke="${STROKE_LIGHT}" stroke-width="8" stroke-linecap="round"/>`,
            `<line x1="${x2 - head}" y1="${tipY1}" x2="${x2}" y2="${svgY}" stroke="${STROKE_LIGHT}" stroke-width="8" stroke-linecap="round"/>`,
            `<line x1="${x2 - head}" y1="${tipY2}" x2="${x2}" y2="${svgY}" stroke="${STROKE_LIGHT}" stroke-width="8" stroke-linecap="round"/>`
        ].join('');
    }
    // ---------------------------------------------------------------


    // FUNCTION | Build SVG for the Rear-Setback Chevron (Top-Right or Top-Left)
    // ------------------------------------------------------------
    // The chevron points "back" (into the page, indicated by an angled
    // stroke on top of the head bar) at the rear leaf's stile edge so the
    // user can see which leaf is in front and which is set back.
    function na_build_setback_glyph(layout) {
        const innerLeft   = layout.stileWidth;
        const innerBottom = layout.baseRail;
        const innerWidth  = layout.openingWidth - 2 * layout.stileWidth;
        const innerHeight = layout.openingHeight - layout.headRail - layout.baseRail;
        const cy = innerBottom + innerHeight - SETBACK_GLYPH_OFFSET_MM;

        const frontIsRight = layout.slideMode === 'FrontSlidesLeft';
        const cx = frontIsRight ? innerLeft + 200 : innerLeft + innerWidth - 200;
        const sign = frontIsRight ? +1 : -1;

        const svgY = -cy;
        const half = SETBACK_GLYPH_LEN_MM / 2;

        return [
            `<polyline points="${cx - half},${svgY} ${cx + sign * half},${svgY - half} ${cx + 3 * sign * half},${svgY}" `,
            `          fill="none" stroke="${STROKE_LIGHT}" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/>`,
            `<text x="${cx + sign * half}" y="${svgY - half - 30}" text-anchor="middle" `,
            `      fill="${STROKE_LIGHT}" font-family="sans-serif" font-size="42" font-weight="600">`,
            `${Math.round(layout.rearSetback)}mm`,
            `</text>`
        ].join('');
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Handle Marker
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for the Handle Dot on the Front (Sliding) Leaf
    // ------------------------------------------------------------
    function na_build_handle_dot(layout) {
        const innerLeft   = layout.stileWidth;
        const innerWidth  = layout.openingWidth - 2 * layout.stileWidth;
        const halfWidth   = innerWidth / 2;
        const frontIsRight = layout.slideMode === 'FrontSlidesLeft';

        const frontCentreX = frontIsRight
            ? innerLeft + halfWidth + (halfWidth / 2)
            : innerLeft + (halfWidth / 2);

        const handleSign = frontIsRight ? +1 : -1;
        const cx = frontCentreX + handleSign * (halfWidth * 0.35);
        const cy = HANDLE_DEFAULT_HEIGHT_MM;

        const svgY = -cy;
        return `<circle cx="${cx}" cy="${svgY}" r="${HANDLE_DOT_RADIUS_MM}" fill="${FILL_HANDLE}" stroke="${STROKE_BLACK}" stroke-width="1.5"/>`;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Public API - Compose the Full Sliding Elevation
    // -----------------------------------------------------------------------------

    // FUNCTION | Generate Full SVG Markup for the Sliding Elevation
    // ------------------------------------------------------------
    // @param  {Object} config - WindowSystem unified config (incl. sliding_door_*)
    // @return {string}        - Inner-SVG markup ready for assignment to innerHTML
    function na_generate_sliding_svg(config) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) {
            console.warn('[NA_EXT_SLIDE_SVG] Na__Viewport__SvgGenerator missing');
            return '';
        }

        const layout = na_resolve_layout(config);

        let svg = '';
        svg += na_build_outer_frame(layout);
        svg += na_build_leaves(layout);
        svg += na_build_setback_glyph(layout);
        svg += na_build_slide_arrow(layout);
        svg += na_build_handle_dot(layout);

        if (layout.showDimensions && typeof sg.na_svgDimensions === 'function') {
            svg += sg.na_svgDimensions(layout.openingWidth, layout.openingHeight);
        }

        return svg;
    }
    // ---------------------------------------------------------------


    // FUNCTION | Legacy Phase-1 API - Returns Wrapped SVG Document
    // ------------------------------------------------------------
    // Kept for any caller still expecting the standalone SVG string. Prefer
    // na_generate_sliding_svg(config) inside the WindowSystem viewport.
    function na_render_elevation_svg(config_hash, viewport_box) {
        const innerSvg = na_generate_sliding_svg(config_hash || {});
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
        na_generate_sliding_svg : na_generate_sliding_svg,
        na_render_elevation_svg : na_render_elevation_svg,
        na_resolve_layout       : na_resolve_layout
    };

    // endregion -------------------------------------------------------------------

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtSlide__ElevationGenerator = Na__ExtSlide__ElevationGenerator;

console.log('[NA_EXT_SLIDE] Sliding Elevation SVG Generator loaded');

// endregion -------------------------------------------------------------------
