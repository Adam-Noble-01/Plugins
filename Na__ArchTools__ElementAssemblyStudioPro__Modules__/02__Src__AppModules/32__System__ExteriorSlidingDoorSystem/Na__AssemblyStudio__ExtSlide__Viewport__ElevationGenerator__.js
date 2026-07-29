/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - SLIDING DOOR ELEVATION SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSlide__Viewport__ElevationGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Renders a 2D elevation SVG of the sliding-door for the
                live preview viewport in the Windows tab. Shows the
                window-style outer frame (per-edge jambs + head + bottom),
                two leaves (front and rear with the rear slightly inset to
                communicate the wall-depth setback), the slide-direction
                arrow on top, the setback indicator on the head, and a
                handle dot on the moving leaf.
   CREATED    : 17-May-2026

   DESCRIPTION:
   - Phase-9: Sliding doors share the WindowSystem's Dimensions /
     Cill & Frame / Glaze Bars sliders, so the layout reads `width_mm`,
     `height_mm`, per-edge `frame_*_thickness_mm`, `has_cill`,
     `cill_height_mm` and the glaze-bar config directly. Legacy
     `sliding_door_opening_*_mm` keys are migrated to the shared keys at
     load time so they no longer appear in the live config.
   - Bulky head/base "track" rectangles are gone. The outer frame is now
     a per-edge jamb + head + bottom rail combo identical to the
     window-mode preview, with an optional cill below.
   - Each leaf can carry a glaze-bar grille when sliding_door_glazed +
     horizontal_glaze_bars / vertical_glaze_bars are configured.
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
     na_getMaterialColor, na_getEffectiveFrameThicknesses (reused for
     visual consistency).
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
    const FILL_CILL_DEFAULT          = '#A0908A';      // <-- Default cill (Sapele) tint
    const DEFAULT_FRAME_MATERIAL_ID  = 'MAT120__GenericWood';
    const DEFAULT_CILL_MATERIAL_ID   = 'MAT541__Timber__Sapele';

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Configuration Resolution
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve a Sanitised Layout Hash from Raw Config
    // ------------------------------------------------------------
    // Phase-9: Reads the shared window-level keys for opening dimensions,
    // per-edge frame thickness, cill and glaze bars; sliding-only keys
    // continue to drive panel layout and slide direction.
    function na_resolve_layout(config) {
        const safeNum    = (value, fallback) => Number.isFinite(Number(value)) ? Number(value) : fallback;
        const openingW   = Math.max(800,  safeNum(config.width_mm,  2400));
        const openingH   = Math.max(1500, safeNum(config.height_mm, 2100));
        const headRail   = Math.max(40, safeNum(config.sliding_door_head_rail_mm,  95));
        const baseRail   = Math.max(80, safeNum(config.sliding_door_base_rail_mm, 200));
        const stileWidth = Math.max(40, safeNum(config.sliding_door_stile_width_mm, 95));
        const rearSet    = Math.max(20, safeNum(config.sliding_door_rear_setback_mm, 60));
        const slideMode  = String(config.sliding_door_mode || 'FrontSlidesRight');
        const isGlazed   = config.sliding_door_glazed !== false;
        const showDims   = config.show_dimensions      !== false;

        const frameEdges = na_resolve_frame_edges(config);
        const cill       = na_resolve_cill(config, frameEdges.bottom);
        const glazeBars  = na_resolve_glazebars(config, isGlazed);
        const leadedGlass = na_resolve_leaded_glass(config, isGlazed);

        const frameMatId = config.frame_material_id || DEFAULT_FRAME_MATERIAL_ID;
        const frameCol   = na_safe_material_colour(frameMatId);

        const innerLeft   = frameEdges.left;
        const innerBottom = frameEdges.bottom;
        const innerWidth  = Math.max(0, openingW - frameEdges.left - frameEdges.right);
        const innerHeight = Math.max(0, openingH - frameEdges.top  - frameEdges.bottom);

        return {
            openingWidth   : openingW,
            openingHeight  : openingH,
            headRail       : headRail,
            baseRail       : baseRail,
            stileWidth     : stileWidth,
            rearSetback    : rearSet,
            slideMode      : slideMode,
            isGlazed       : isGlazed,
            showDimensions : showDims,
            frameEdges     : frameEdges,
            cill           : cill,
            glazeBars      : glazeBars,
            leadedGlass    : leadedGlass,
            frameColour    : frameCol,
            innerLeft      : innerLeft,
            innerBottom    : innerBottom,
            innerWidth     : innerWidth,
            innerHeight    : innerHeight
        };
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Resolve Per-Edge Frame Thicknesses (Shared With Window Generator)
    // ------------------------------------------------------------
    function na_resolve_frame_edges(config) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (sg && typeof sg.na_getEffectiveFrameThicknesses === 'function') {
            return sg.na_getEffectiveFrameThicknesses(config);
        }
        const uniform = (config.frame_thickness_mm != null) ? Number(config.frame_thickness_mm) : 50;
        const useAdv  = config.advanced_frame_controls === true;
        const pick    = (sideKey) => {
            const raw = useAdv ? config[sideKey] : uniform;
            return Math.max(0, Number(raw != null ? raw : uniform));
        };
        return {
            top:    pick('frame_top_thickness_mm'),
            bottom: pick('frame_bottom_thickness_mm'),
            left:   pick('frame_left_thickness_mm'),
            right:  pick('frame_right_thickness_mm')
        };
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Resolve Cill Configuration With Material-Aware Tint
    // ------------------------------------------------------------
    function na_resolve_cill(config, bottomFrameThickness) {
        const enabled  = config.has_cill === true && bottomFrameThickness > 0;
        const heightMm = Math.max(20, Number(config.cill_height_mm != null ? config.cill_height_mm : 50));
        const paint    = config.paint_cill === true;
        const matId    = paint ? (config.frame_material_id || DEFAULT_FRAME_MATERIAL_ID) : DEFAULT_CILL_MATERIAL_ID;
        const colour   = paint ? na_safe_material_colour(matId) : FILL_CILL_DEFAULT;
        return { enabled: enabled, heightMm: heightMm, colour: colour };
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Resolve Glaze-Bar Grille Settings (Phase-9)
    // ------------------------------------------------------------
    function na_resolve_glazebars(config, isGlazed) {
        const hBars   = Math.max(0, Math.round(Number(config.horizontal_glaze_bars || 0)));
        const vBars   = Math.max(0, Math.round(Number(config.vertical_glaze_bars   || 0)));
        const barW    = Math.max(8, Number(config.glaze_bar_width_mm || 25));
        const advanced = {
            marginEnabled : config.glazebar_margin_enabled === true,
            marginOffset  : Math.max(0, Number(config.glazebar_margin_offset_mm || 0)),
            archEnabled   : config.glazebar_gothic_arch_enabled === true,
            archAmount    : Math.max(1, Math.min(8, Math.round(config.glazebar_gothic_arch_amount || 2))),     // <-- V1.9.4 Allow single lancet arch
            archHeight    : Math.max(0, Number(config.glazebar_gothic_arch_height_mm || 0)),
            hOffsetMm     : Number(config.glazebar_horizontal_offset_mm || 0),                      // <-- Uniform vertical nudge for horizontal bars (positive = up)
            hOffsetsMm    : window.Na__GlazebarMath ? window.Na__GlazebarMath.na_collectBarOffsets(config, 'glazebar_h_offset_', hBars) : [],   // <-- Per-bar vertical nudges
            vOffsetsMm    : window.Na__GlazebarMath ? window.Na__GlazebarMath.na_collectBarOffsets(config, 'glazebar_v_offset_', vBars) : []    // <-- Per-bar horizontal nudges
        };
        const enabled = isGlazed && (hBars > 0 || vBars > 0 || advanced.archEnabled);
        return { enabled: enabled, hBars: hBars, vBars: vBars, barW: barW, advanced: advanced };
    }
    // ---------------------------------------------------------------

    // SUB FUNCTION | Resolve Leaded Glass Overlay Settings
    // ------------------------------------------------------------
    function na_resolve_leaded_glass(config, isGlazed) {
        const sg = window.Na__Viewport__SvgGenerator;
        let colourId = 'MTE104__LineColour__MidGrey__L60';
        if (sg && typeof sg.na_resolveLeadedColourId === 'function') {
            colourId = sg.na_resolveLeadedColourId(config);
        } else if (config && config.edge_colour_leaded_id) {
            colourId = String(config.edge_colour_leaded_id);
        }
        return {
            enabled     : isGlazed && config.leaded_glass_enabled === true,
            hBars       : Math.max(0, Math.min(8, Math.round(Number(config.horizontal_leaded_bars || 0)))),
            vBars       : Math.max(0, Math.min(8, Math.round(Number(config.vertical_leaded_bars || 0)))),
            widthMm     : Math.max(2, Number(config.leaded_width_mm || 6)),
            centreLines : config.leaded_centre_lines_only === true,
            colourId    : colourId
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
    // REGION | Outer Frame + Optional Cill Drawing (Phase-9)
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for the Window-Style Opening Frame
    // ------------------------------------------------------------
    function na_build_outer_frame(layout) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg || typeof sg.na_svgRect !== 'function') return '';

        const w   = layout.openingWidth;
        const h   = layout.openingHeight;
        const fE  = layout.frameEdges;
        const col = layout.frameColour;
        let svg   = '';

        if (fE.left > 0) {
            svg += sg.na_svgRect(0, 0, fE.left, h, col, STROKE_BLACK, 1);
        }
        if (fE.right > 0) {
            svg += sg.na_svgRect(w - fE.right, 0, fE.right, h, col, STROKE_BLACK, 1);
        }
        if (fE.top > 0) {
            const innerW = Math.max(0, w - fE.left - fE.right);
            svg += sg.na_svgRect(fE.left, h - fE.top, innerW, fE.top, col, STROKE_BLACK, 1);
        }
        if (fE.bottom > 0) {
            const innerW = Math.max(0, w - fE.left - fE.right);
            svg += sg.na_svgRect(fE.left, 0, innerW, fE.bottom, col, STROKE_BLACK, 1);
        }
        return svg;
    }
    // ---------------------------------------------------------------


    // FUNCTION | Build SVG for the Optional Cill Below the Frame
    // ------------------------------------------------------------
    function na_build_cill(layout) {
        if (!layout.cill.enabled) return '';
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg || typeof sg.na_svgRect !== 'function') return '';

        return sg.na_svgRect(
            0, -layout.cill.heightMm,
            layout.openingWidth, layout.cill.heightMm,
            layout.cill.colour, STROKE_BLACK, 1
        );
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
        if (layout.innerWidth <= 0 || layout.innerHeight <= 0) return '';

        const halfWidth = layout.innerWidth / 2;
        const leafW     = halfWidth + (PANEL_OVERLAP_MM / 2);

        const frontIsRight = layout.slideMode === 'FrontSlidesLeft';
        const frontX       = frontIsRight ? layout.innerLeft + halfWidth - (PANEL_OVERLAP_MM / 2) : layout.innerLeft;
        const rearX        = frontIsRight ? layout.innerLeft : layout.innerLeft + halfWidth - (PANEL_OVERLAP_MM / 2);

        let svg = '';
        svg += na_build_one_leaf(rearX,  layout.innerBottom, leafW, layout.innerHeight, layout, FILL_GLAZING_REAR,  true);
        svg += na_build_one_leaf(frontX, layout.innerBottom, leafW, layout.innerHeight, layout, FILL_GLAZING_FRONT, false);
        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Build SVG for a Single Sliding Leaf (Window-Style Joinery)
    // ------------------------------------------------------------
    // Phase-9 joinery: stiles span the FULL leaf height, rails fit
    // between stiles. Glazing and glaze bars share the same clear inner
    // rectangle so a glaze-bar grille lines up with the glass pane.
    function na_build_one_leaf(leafX, leafY, leafWidth, leafHeight, layout, glazingColour, isRear) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) return '';

        const colour    = layout.frameColour;
        const stile     = Math.min(layout.stileWidth, leafWidth * 0.18);
        const headRail  = Math.min(layout.headRail,   leafHeight * 0.20);
        const baseRail  = Math.min(layout.baseRail,   leafHeight * 0.30);

        const glazedX  = leafX + stile;
        const glazedY  = leafY + baseRail;
        const glazedW  = Math.max(0, leafWidth  - 2 * stile);
        const glazedH  = Math.max(0, leafHeight - baseRail - headRail);

        let svg = '';
        if (glazedW > 0 && glazedH > 0) {
            const fill = layout.isGlazed ? glazingColour : (isRear ? '#A8B2BE' : colour);
            svg += sg.na_svgRect(glazedX, glazedY, glazedW, glazedH, fill, STROKE_BLACK, 1);
        }

        if (leafHeight > 0) {
            svg += sg.na_svgRect(leafX, leafY, stile, leafHeight, colour, STROKE_BLACK, 1);
            svg += sg.na_svgRect(leafX + leafWidth - stile, leafY, stile, leafHeight, colour, STROKE_BLACK, 1);
        }

        const railX = leafX + stile;
        const railW = Math.max(0, leafWidth - 2 * stile);
        if (railW > 0 && baseRail > 0) {
            svg += sg.na_svgRect(railX, leafY, railW, baseRail, colour, STROKE_BLACK, 1);
        }
        if (railW > 0 && headRail > 0) {
            svg += sg.na_svgRect(railX, leafY + leafHeight - headRail, railW, headRail, colour, STROKE_BLACK, 1);
        }

        if (layout.glazeBars.enabled && glazedW > 0 && glazedH > 0) {
            svg += na_build_leaf_glazebars(glazedX, glazedY, glazedW, glazedH, layout);
        }

        if (layout.leadedGlass && layout.leadedGlass.enabled && glazedW > 0 && glazedH > 0) {
            const sgLead = window.Na__Viewport__SvgGenerator;
            if (sgLead && typeof sgLead.na_generateLeadedGlassSvg === 'function') {
                svg += sgLead.na_generateLeadedGlassSvg(glazedX, glazedY, glazedW, glazedH, layout.leadedGlass, {
                    hBars: layout.glazeBars.hBars,                     // <-- Per-cell layout between glaze bars (render parity;
                    vBars: layout.glazeBars.vBars,                     //     no click-toggle on sliding leaves yet)
                    barWidth: layout.glazeBars.barW,
                    advancedGlazebar: layout.glazeBars.advanced
                });
            }
        }

        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Draw Horizontal + Vertical Glaze Bars Inside a Leaf
    // ------------------------------------------------------------
    function na_build_leaf_glazebars(glassX, glassY, glassW, glassH, layout) {
        const sg   = window.Na__Viewport__SvgGenerator;
        const math = window.Na__GlazebarMath;
        if (!sg || !math) return '';

        const { hBars, vBars, barW, advanced } = layout.glazeBars;
        const adv     = advanced || { marginEnabled:false, marginOffset:0, archEnabled:false, archAmount:0, archHeight:0 };
        const colour  = layout.frameColour;
        let svg = '';

        // Subtract the FULL arch zone (apex + overshoot) so overshoot
        // termini land at top of glass, matching window-mode.
        const effectiveGlassH = math.na_computeEffectiveGlassHeight(glassH, adv.archEnabled, adv.archHeight, glassW, adv.archAmount);

        if (hBars > 0 && effectiveGlassH > 0) {
            const hPosRaw = math.na_computeBarPositions(glassY, effectiveGlassH, hBars, adv.marginEnabled, adv.marginOffset);
            const hOffsetMm = Number(adv.hOffsetMm || 0);
            let hPos = hOffsetMm === 0
                ? hPosRaw
                : hPosRaw.map(function (y) { return y + hOffsetMm; });
            hPos = math.na_applyBarOffsets(hPos, adv.hOffsetsMm);       // <-- Per-bar vertical nudges after uniform offset
            for (let i = 0; i < hPos.length; i += 1) {
                svg += sg.na_svgRect(glassX, hPos[i] - barW / 2, glassW, barW, colour, STROKE_BLACK, 1);
            }
        }
        if (vBars > 0 && effectiveGlassH > 0) {
            let vPos = math.na_computeBarPositions(glassX, glassW, vBars, adv.marginEnabled, adv.marginOffset);
            vPos = math.na_applyBarOffsets(vPos, adv.vOffsetsMm);       // <-- Per-bar horizontal nudges after spacing
            for (let i = 0; i < vPos.length; i += 1) {
                svg += sg.na_svgRect(vPos[i] - barW / 2, glassY, barW, effectiveGlassH, colour, STROKE_BLACK, 1);
            }
        }
        if (adv.archEnabled && adv.archHeight > 0 && adv.archAmount >= 1 && typeof sg.na_generateGothicArchSvg === 'function') {
            const springingY = glassY + effectiveGlassH;
            svg += sg.na_generateGothicArchSvg(
                glassX, springingY, glassW, adv.archHeight, adv.archAmount, barW, colour,
                { openingIndex: 0, cellIndex: 0, panelIndex: 0, sashIndex: 0 }
            );
        }
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
        if (layout.innerWidth <= 0 || layout.innerHeight <= 0) return '';

        const arrowY = layout.innerBottom + layout.innerHeight - SLIDE_ARROW_OFFSET_MM;
        const cx     = layout.innerLeft   + layout.innerWidth / 2;
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
    function na_build_setback_glyph(layout) {
        if (layout.innerWidth <= 0 || layout.innerHeight <= 0) return '';

        const cy = layout.innerBottom + layout.innerHeight - SETBACK_GLYPH_OFFSET_MM;

        const frontIsRight = layout.slideMode === 'FrontSlidesLeft';
        const cx = frontIsRight ? layout.innerLeft + 200 : layout.innerLeft + layout.innerWidth - 200;
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
        if (layout.innerWidth <= 0) return '';

        const halfWidth    = layout.innerWidth / 2;
        const frontIsRight = layout.slideMode === 'FrontSlidesLeft';

        const frontCentreX = frontIsRight
            ? layout.innerLeft + halfWidth + (halfWidth / 2)
            : layout.innerLeft + (halfWidth / 2);

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
    function na_generate_sliding_svg(config) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) {
            console.warn('[NA_EXT_SLIDE_SVG] Na__Viewport__SvgGenerator missing');
            return '';
        }

        const layout = na_resolve_layout(config);

        let svg = '';
        svg += na_build_outer_frame(layout);
        svg += na_build_cill(layout);
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
