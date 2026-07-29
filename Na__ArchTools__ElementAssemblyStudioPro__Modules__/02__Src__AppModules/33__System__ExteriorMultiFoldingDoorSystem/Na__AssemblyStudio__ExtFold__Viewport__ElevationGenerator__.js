/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - BIFOLD DOOR ELEVATION SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtFold__Viewport__ElevationGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Renders a 2D elevation SVG of the bifold-door for the
                live preview viewport in the Windows tab. Shows N panels,
                a window-style opening frame (per-edge jambs + head + bottom),
                an optional cill beneath the frame, glazing, hinge dots,
                fold-pattern indicator arrows, dimensions, and handle
                placement on the leading slave panel(s). Drawn in millimetre
                coordinate space using bottom-left origin convention so the
                existing Na__Viewport__Controls.na_windowResetFitter padding
                works directly.
   CREATED    : 17-May-2026

   DESCRIPTION:
   - Phase-9: Bifold doors share the WindowSystem's Dimensions / Cill &
     Frame / Glaze Bars sliders, so the layout reads `width_mm`,
     `height_mm`, per-edge `frame_*_thickness_mm`, `has_cill`,
     `cill_height_mm` etc. directly. Legacy `bifold_door_opening_*_mm`
     keys are migrated to the shared keys at load time so they no longer
     appear in the live config.
   - Bulky head/base "track" rectangles are gone. The outer frame is now
     a per-edge jamb + head + bottom rail combo identical to the
     window-mode preview, with an optional cill below.
   - Panel content is driven by `bifold_door_leaf_composition` via
     Na__ExtFold__PanelConfigResolver (FullyGlazed / GlazedOverFielded /
     FullyFielded) with field cells, midrail, and glaze bars confined to
     the glazed region. Legacy `bifold_door_glazed` is a fallback only.
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
     na_getMaterialColor, na_getEffectiveFrameThicknesses (reused for
     visual consistency).
   - window.Na__ExtFold__PanelConfigResolver for composition / field cells.
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
    const FILL_CILL_DEFAULT              = '#A0908A';      // <-- Default cill (Sapele) tint
    const DEFAULT_FRAME_MATERIAL_ID      = 'MAT120__GenericWood';
    const DEFAULT_CILL_MATERIAL_ID       = 'MAT541__Timber__Sapele';

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Configuration Resolution
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve a Sanitised Layout Hash from Raw Config
    // ------------------------------------------------------------
    // Phase-9: Reads the shared window-level keys for opening dimensions,
    // per-edge frame thickness, cill and glaze bars; bifold-only keys
    // continue to drive panel layout, joinery and fold direction.
    // Composition / fielded panel content is resolved via
    // Na__ExtFold__PanelConfigResolver (see na_generate_bifold_svg).
    function na_resolve_layout(config) {
        const safeNum    = (value, fallback) => Number.isFinite(Number(value)) ? Number(value) : fallback;
        const openingW   = Math.max(800,  safeNum(config.width_mm,  3600));
        const openingH   = Math.max(1500, safeNum(config.height_mm, 2100));
        const panelCount = Math.max(2, Math.min(8, Math.round(safeNum(config.bifold_door_panel_count, 4))));
        const headRail   = Math.max(40, safeNum(config.bifold_door_head_rail_mm,  95));
        const baseRail   = Math.max(80, safeNum(config.bifold_door_base_rail_mm, 200));
        const stileWidth = Math.max(40, safeNum(config.bifold_door_stile_width_mm, 95));
        const layout     = String(config.bifold_door_layout      || 'EqualEqual');
        const openSide   = String(config.bifold_door_open_side   || 'Right');
        const masterSide = String(config.bifold_door_master_side || 'Right');
        const showDims   = config.show_dimensions    !== false;

        const panelSettings = (window.Na__ExtFold__PanelConfigResolver &&
            typeof window.Na__ExtFold__PanelConfigResolver.na_panel_settings === 'function')
            ? window.Na__ExtFold__PanelConfigResolver.na_panel_settings(config)
            : {
                composition: config.bifold_door_leaf_composition ||
                    (config.bifold_door_glazed === false ? 'FullyFielded' : 'FullyGlazed')
            };
        const isGlazed = panelSettings.composition !== 'FullyFielded';

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
        const panelWidth  = panelCount > 0 ? innerWidth / panelCount : 0;

        return {
            openingWidth     : openingW,
            openingHeight    : openingH,
            panelCount       : panelCount,
            headRail         : headRail,
            baseRail         : baseRail,
            stileWidth       : stileWidth,
            layout           : layout,
            openSide         : openSide,
            masterSide       : masterSide,
            isGlazed         : isGlazed,
            composition      : panelSettings.composition,
            panelSettings    : panelSettings,
            showDimensions   : showDims,
            frameEdges       : frameEdges,
            cill             : cill,
            glazeBars        : glazeBars,
            leadedGlass      : leadedGlass,
            removedGlazebars : na_key_set(config.removed_glazebars),
            disabledLeadedCells : na_key_set(config.leaded_disabled_cells),
            frameColour      : frameCol,
            innerLeft        : innerLeft,
            innerBottom      : innerBottom,
            innerWidth       : innerWidth,
            innerHeight      : innerHeight,
            panelWidth       : panelWidth
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
            hBars       : Math.max(0, Math.min(10, Math.round(Number(config.horizontal_leaded_bars || 0)))),
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


    // HELPER FUNCTION | Build a String-Key Set From a Config Array
    // ------------------------------------------------------------
    function na_key_set(source) {
        return new Set(Array.isArray(source) ? source.map(function (key) { return String(key); }) : []);
    }
    // ---------------------------------------------------------------


    // HELPER FUNCTION | Per-Panel Context for Shared Click-Target Keys
    // ------------------------------------------------------------
    function na_panel_context(panelIndex) {
        return { openingIndex: 0, cellIndex: 0, panelIndex: panelIndex, sashIndex: 0 };
    }
    // ---------------------------------------------------------------


    // HELPER FUNCTION | Empty Click-Target Accumulation Bucket
    // ------------------------------------------------------------
    function na_create_click_bucket() {
        return { clickTargetsSvg: '', leadedClickTargetsSvg: '' };
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
    // REGION | Outer Frame + Optional Cill Drawing (Phase-9)
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for the Window-Style Opening Frame
    // ------------------------------------------------------------
    // Replaces the previous bulky head/base track casings with a window
    // identical per-edge frame: left jamb (full height), right jamb (full
    // height), head rail (between jambs), bottom rail (between jambs).
    // Skips edges with zero thickness.
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
    // REGION | Per-Panel Drawing (Stiles, Rails, Glazing, Fielded Panels)
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for All Bifold Panels Inside the Inner Clear Opening
    // ------------------------------------------------------------
    // @delegate: Na__AssemblyStudio__ExtFold__UiSystem__PanelConfigResolver__.js
    function na_build_all_panels(layout, resolvedPanels, clickBucket) {
        let svg = '';
        if (layout.innerWidth <= 0 || layout.innerHeight <= 0) return svg;

        const panels = resolvedPanels && resolvedPanels.length
            ? resolvedPanels
            : null;

        if (panels) {
            for (let i = 0; i < panels.length; i += 1) {
                const panelIndex = Number.isFinite(Number(panels[i].index))
                    ? Number(panels[i].index)
                    : i;
                svg += na_build_one_panel_from_resolved(panels[i], layout, panelIndex, clickBucket);
            }
            return svg;
        }

        for (let i = 0; i < layout.panelCount; i++) {
            const px = layout.innerLeft + i * layout.panelWidth + (PANEL_GAP_MM / 2);
            const py = layout.innerBottom;
            const pw = Math.max(0, layout.panelWidth - PANEL_GAP_MM);
            const ph = layout.innerHeight;
            svg += na_build_one_panel_legacy(px, py, pw, ph, layout, i, clickBucket);
        }
        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Build SVG for One Panel from PanelConfigResolver Output
    // ------------------------------------------------------------
    // Draws stiles/rails, optional midrail, glazed region + bars/leaded,
    // and field cells (linework or raised bevel outline) for non-glazed
    // compositions — parity with ExtDouble elevation leaf drawing.
    function na_build_one_panel_from_resolved(panel, layout, panelIndex, clickBucket) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) return '';

        const colour = layout.frameColour;
        const settings = panel.settings || layout.panelSettings || {};
        const pl = panel.panelLayout || {};
        const stile = pl.stileMm != null ? pl.stileMm : Math.min(layout.stileWidth, panel.widthMm * 0.30);
        const headRail = pl.topRailMm != null ? pl.topRailMm : Math.min(layout.headRail, panel.heightMm * 0.25);
        const baseRail = pl.bottomRailMm != null ? pl.bottomRailMm : Math.min(layout.baseRail, panel.heightMm * 0.35);
        const midRail = pl.midRailMm != null ? pl.midRailMm : (settings.midRailMm || 120);

        const panelX = panel.originXMm;
        const panelY = panel.originZMm;
        const panelWidth = panel.widthMm;
        const panelHeight = panel.heightMm;

        let svg = '';

        if (pl.fieldRegion && pl.fieldRegion.widthMm > 0 && pl.fieldRegion.heightMm > 0) {
            const f = pl.fieldRegion;
            svg += sg.na_svgRect(f.xMm, f.zMm, f.widthMm, f.heightMm, colour, STROKE_BLACK, 1);
        }

        if (pl.glazedRegion && pl.glazedRegion.widthMm > 0 && pl.glazedRegion.heightMm > 0) {
            const g = pl.glazedRegion;
            svg += sg.na_svgRect(g.xMm, g.zMm, g.widthMm, g.heightMm, FILL_GLAZING, STROKE_BLACK, 1);
            if (layout.glazeBars.enabled) {
                svg += na_build_panel_glazebars(g.xMm, g.zMm, g.widthMm, g.heightMm, layout, panelIndex, clickBucket);
            }
            svg += na_build_panel_leaded(g.xMm, g.zMm, g.widthMm, g.heightMm, layout, panelIndex, clickBucket);
        }

        if (panelHeight > 0) {
            svg += sg.na_svgRect(panelX, panelY, stile, panelHeight, colour, STROKE_BLACK, 1);
            svg += sg.na_svgRect(panelX + panelWidth - stile, panelY, stile, panelHeight, colour, STROKE_BLACK, 1);
        }

        const railX = panelX + stile;
        const railW = Math.max(0, panelWidth - 2 * stile);
        if (railW > 0 && baseRail > 0) {
            svg += sg.na_svgRect(railX, panelY, railW, baseRail, colour, STROKE_BLACK, 1);
        }
        if (railW > 0 && headRail > 0) {
            svg += sg.na_svgRect(railX, panelY + panelHeight - headRail, railW, headRail, colour, STROKE_BLACK, 1);
        }

        if (settings.composition === 'GlazedOverFielded' && pl.fieldRegion && midRail > 0) {
            const midZ = pl.fieldRegion.zMm + pl.fieldRegion.heightMm;
            svg += sg.na_svgRect(railX, midZ, railW, midRail, colour, STROKE_BLACK, 1);
        }

        if (pl.fieldDividers && pl.fieldDividers.length) {
            pl.fieldDividers.forEach(function (divider) {
                svg += sg.na_svgRect(
                    divider.xMm, divider.zMm, divider.widthMm, divider.heightMm,
                    colour, STROKE_BLACK, 1
                );
            });
        }

        if (pl.fieldCells && pl.fieldCells.length) {
            svg += na_build_field_cells(pl.fieldCells, settings, colour, sg);
        }

        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Draw Field Cell Insets (Linework or Raised Outline)
    // ------------------------------------------------------------
    function na_build_field_cells(fieldCells, settings, colour, sg) {
        let svg = '';
        const outputMode = settings.outputMode || 'ThreeDimensional';
        const profile = settings.profile || 'RaisedBevelled';
        const insetDefault = settings.insetMm || 25;
        const bevelDefault = settings.bevelMm || 18;

        fieldCells.forEach(function (cell) {
            const inset = Math.min(insetDefault, cell.widthMm / 3, cell.heightMm / 3);
            const fill = outputMode === 'Linework' ? 'none' : colour;
            const strokeWidth = outputMode === 'Linework' ? 1 : 3;
            svg += sg.na_svgRect(
                cell.xMm + inset,
                cell.zMm + inset,
                cell.widthMm - 2 * inset,
                cell.heightMm - 2 * inset,
                fill, STROKE_BLACK, strokeWidth
            );
            if (outputMode === 'ThreeDimensional' && profile === 'RaisedBevelled') {
                const bevel = Math.min(bevelDefault, inset);
                svg += sg.na_svgRect(
                    cell.xMm + bevel,
                    cell.zMm + bevel,
                    cell.widthMm - 2 * bevel,
                    cell.heightMm - 2 * bevel,
                    'none', STROKE_BLACK, 1
                );
            }
        });
        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Legacy Fully-Glazed Panel Draw (Resolver Unavailable)
    // ------------------------------------------------------------
    function na_build_one_panel_legacy(panelX, panelY, panelWidth, panelHeight, layout, panelIndex, clickBucket) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) return '';

        const colour    = layout.frameColour;
        const stile     = Math.min(layout.stileWidth, panelWidth * 0.30);
        const headRail  = Math.min(layout.headRail,   panelHeight * 0.25);
        const baseRail  = Math.min(layout.baseRail,   panelHeight * 0.35);

        const glazedX  = panelX + stile;
        const glazedY  = panelY + baseRail;
        const glazedW  = Math.max(0, panelWidth  - 2 * stile);
        const glazedH  = Math.max(0, panelHeight - baseRail - headRail);

        let svg = '';

        if (glazedW > 0 && glazedH > 0) {
            const fillCol = layout.isGlazed ? FILL_GLAZING : colour;
            svg += sg.na_svgRect(glazedX, glazedY, glazedW, glazedH, fillCol, STROKE_BLACK, 1);
        }

        if (panelHeight > 0) {
            svg += sg.na_svgRect(panelX, panelY, stile, panelHeight, colour, STROKE_BLACK, 1);
            svg += sg.na_svgRect(panelX + panelWidth - stile, panelY, stile, panelHeight, colour, STROKE_BLACK, 1);
        }

        const railX = panelX + stile;
        const railW = Math.max(0, panelWidth - 2 * stile);
        if (railW > 0 && baseRail > 0) {
            svg += sg.na_svgRect(railX, panelY, railW, baseRail, colour, STROKE_BLACK, 1);
        }
        if (railW > 0 && headRail > 0) {
            svg += sg.na_svgRect(railX, panelY + panelHeight - headRail, railW, headRail, colour, STROKE_BLACK, 1);
        }

        if (layout.glazeBars.enabled && glazedW > 0 && glazedH > 0) {
            svg += na_build_panel_glazebars(glazedX, glazedY, glazedW, glazedH, layout, panelIndex, clickBucket);
        }

        if (glazedW > 0 && glazedH > 0) {
            svg += na_build_panel_leaded(glazedX, glazedY, glazedW, glazedH, layout, panelIndex, clickBucket);
        }

        return svg;
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Draw Horizontal + Vertical Glaze Bars Inside a Panel
    // ------------------------------------------------------------
    // Delegates to the shared WindowSystem grille builder so removed-bar
    // state and invisible click targets stay in sync with Window / Double Door.
    function na_build_panel_glazebars(glassX, glassY, glassW, glassH, layout, panelIndex, clickBucket) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg || typeof sg.na_generateGlazeBarsSvg !== 'function') return '';

        const { hBars, vBars, barW, advanced } = layout.glazeBars;
        const bucket = sg.na_generateGlazeBarsSvg(
            glassX, glassY, glassW, glassH,
            hBars, vBars, barW, layout.frameColour,
            na_panel_context(panelIndex),
            layout.removedGlazebars || new Set(),
            advanced
        );
        if (clickBucket) {
            clickBucket.clickTargetsSvg += bucket.clickTargetsSvg || '';
        }
        return bucket.svg || '';
    }
    // ---------------------------------------------------------------


    // SUB FUNCTION | Draw Leaded Glass With Per-Cell Click Targets
    // ------------------------------------------------------------
    function na_build_panel_leaded(glassX, glassY, glassW, glassH, layout, panelIndex, clickBucket) {
        if (!layout.leadedGlass || !layout.leadedGlass.enabled) return '';
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg || typeof sg.na_generateLeadedGlassSvg !== 'function') return '';

        const leadedOpts = Object.assign({}, layout.leadedGlass, {
            disabledCells: layout.disabledLeadedCells || new Set()
        });
        return sg.na_generateLeadedGlassSvg(glassX, glassY, glassW, glassH, leadedOpts, {
            hBars: layout.glazeBars.hBars,
            vBars: layout.glazeBars.vBars,
            barWidth: layout.glazeBars.barW,
            advancedGlazebar: layout.glazeBars.advanced,
            panelContext: na_panel_context(panelIndex),
            clickBucket: clickBucket
        });
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Hinge Dot & Fold Arrow Indicators
    // -----------------------------------------------------------------------------

    // FUNCTION | Build SVG for All Hinge Dots
    // ------------------------------------------------------------
    function na_build_hinge_dots(layout, foldDirections) {
        const innerLeft   = layout.innerLeft;
        const innerBottom = layout.innerBottom;
        const innerWidth  = layout.innerWidth;
        const innerHeight = layout.innerHeight;
        const topY        = innerBottom + innerHeight - 100;
        const botY        = innerBottom + 100;
        const panelStep   = layout.panelWidth;

        let svg = '';
        if (innerWidth <= 0 || innerHeight <= 0) return svg;

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
    function na_build_fold_arrows(layout, foldDirections) {
        const innerLeft   = layout.innerLeft;
        const innerBottom = layout.innerBottom;
        const innerWidth  = layout.innerWidth;
        const innerHeight = layout.innerHeight;
        const arrowY      = innerBottom + innerHeight - FOLD_ARROW_OFFSET_FROM_TOP_MM;
        const panelStep   = layout.panelWidth;

        let svg = '';
        if (innerWidth <= 0 || innerHeight <= 0) return svg;

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
    function na_build_handle_dot(layout, foldDirections) {
        const innerLeft   = layout.innerLeft;
        const innerWidth  = layout.innerWidth;
        const panelStep   = layout.panelWidth;
        if (innerWidth <= 0) return '';

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
    function na_generate_bifold_svg(config) {
        const sg = window.Na__Viewport__SvgGenerator;
        if (!sg) {
            console.warn('[NA_EXT_FOLD_SVG] Na__Viewport__SvgGenerator missing');
            return '';
        }

        const layout         = na_resolve_layout(config);
        const foldDirections = na_resolve_fold_directions(layout);
        const clickBucket    = na_create_click_bucket();

        // @delegate: Na__AssemblyStudio__ExtFold__UiSystem__PanelConfigResolver__.js
        let resolvedPanels = null;
        if (window.Na__ExtFold__PanelConfigResolver &&
            typeof window.Na__ExtFold__PanelConfigResolver.na_resolve === 'function') {
            const panelResolved = window.Na__ExtFold__PanelConfigResolver.na_resolve(config || {});
            resolvedPanels = panelResolved.panels || null;
            if (panelResolved.settings) {
                layout.panelSettings = panelResolved.settings;
                layout.composition = panelResolved.settings.composition;
                layout.isGlazed = panelResolved.settings.composition !== 'FullyFielded';
            }
        }

        let svg = '';
        svg += na_build_outer_frame(layout);
        svg += na_build_cill(layout);
        svg += na_build_all_panels(layout, resolvedPanels, clickBucket);
        svg += na_build_hinge_dots(layout, foldDirections);
        svg += na_build_fold_arrows(layout, foldDirections);
        svg += na_build_handle_dot(layout, foldDirections);

        if (layout.showDimensions && typeof sg.na_svgDimensions === 'function') {
            svg += sg.na_svgDimensions(layout.openingWidth, layout.openingHeight);
        }

        svg += clickBucket.leadedClickTargetsSvg;                        // <-- Below glazebar targets so bar clicks win
        svg += clickBucket.clickTargetsSvg;

        return svg;
    }
    // ---------------------------------------------------------------


    // FUNCTION | Legacy Phase-1 API - Returns Wrapped SVG Document
    // ------------------------------------------------------------
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
