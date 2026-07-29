/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR MULTIFOLD DOOR - PANEL CONFIG RESOLVER
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtFold__UiSystem__PanelConfigResolver__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Resolve shared bifold_door_* panel settings and per-panel
                fielded / glazed layouts for the live elevation preview.
                One composition applies to every panel in the set.

   DESCRIPTION:
   - Mirrors ExtDouble LeafConfigResolver panel-layout math, but without
     per-leaf overrides (bifold uses one shared config for all panels).
   - Composition prefers bifold_door_leaf_composition; falls back to legacy
     bifold_door_glazed when the composition key is absent.
   - Consumed by Na__ExtFold__ElevationGenerator.

   ============================================================================= */


// =============================================================================
// REGION | ExtFold Panel Config Resolver Module
// =============================================================================

const Na__ExtFold__PanelConfigResolver = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | Constants
    // -----------------------------------------------------------------------------

    const PANEL_GAP_MM = 4;
    const NA_PRESETS = {
        OnePanel      : [1, 1],
        TwoVertical   : [2, 1],
        TwoHorizontal : [1, 2],
        FourPanel     : [2, 2],
        SixPanel      : [2, 3]
    };
    const NA_COMPOSITIONS = {
        FullyGlazed       : true,
        GlazedOverFielded : true,
        FullyFielded      : true
    };

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Scalar Helpers
    // -----------------------------------------------------------------------------

    function na_number(value, fallback) {
        const number = Number(value);
        return Number.isFinite(number) ? number : fallback;
    }

    function na_boolean(value, fallback) {
        if (value === undefined || value === null) return fallback;
        return value === true || String(value).toLowerCase() === 'true';
    }

    function na_clamp(value, minimum, maximum) {
        return Math.min(maximum, Math.max(minimum, na_number(value, minimum)));
    }

    function na_collect_bar_offsets(config, prefix, count) {
        const offsets = [];
        for (let barIndex = 1; barIndex <= count; barIndex += 1) {
            offsets.push(na_number(config[prefix + barIndex + '_mm'], 0));
        }
        return offsets;
    }

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Shared Panel Settings
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve Shared Fielded-Panel Settings from Bifold Config
    // ------------------------------------------------------------
    function na_panel_settings(config) {
        config = config || {};

        let composition = config.bifold_door_leaf_composition;
        if (!composition || !NA_COMPOSITIONS[composition]) {
            composition = config.bifold_door_glazed === false ? 'FullyFielded' : 'FullyGlazed';
        }

        const horizontalBars = na_clamp(config.horizontal_glaze_bars || 0, 0, 12);
        const verticalBars   = na_clamp(config.vertical_glaze_bars || 0, 0, 12);

        return {
            composition         : composition,
            outputMode          : config.bifold_door_panel_output_mode || 'ThreeDimensional',
            profile             : config.bifold_door_panel_profile || 'RaisedBevelled',
            preset              : config.bifold_door_panel_preset || 'OnePanel',
            columns             : na_clamp(config.bifold_door_panel_columns, 1, 6),
            rows                : na_clamp(config.bifold_door_panel_rows, 1, 6),
            fieldedHeightMm     : na_number(config.bifold_door_fielded_section_height_mm, 300),
            midRailMm           : na_number(config.bifold_door_mid_rail_width_mm, 120),
            stileMm             : na_number(config.bifold_door_stile_width_mm, 95),
            topRailMm           : na_number(config.bifold_door_head_rail_mm, 95),
            bottomRailMm        : na_number(config.bifold_door_base_rail_mm, 200),
            insetMm             : na_number(config.bifold_door_panel_inset_mm, 25),
            depthMm             : na_number(config.bifold_door_panel_depth_mm, 12),
            bevelMm             : na_number(config.bifold_door_panel_bevel_width_mm, 18),
            horizontalBars      : horizontalBars,
            verticalBars        : verticalBars,
            glazeBarWidthMm     : na_clamp(config.glaze_bar_width_mm || 25, 5, 100),
            glazeBarInsetMm     : na_clamp(config.glazebar_inset_mm || 10, 0, 100),
            marginEnabled       : na_boolean(config.glazebar_margin_enabled, false),
            marginOffsetMm      : Math.max(0, na_number(config.glazebar_margin_offset_mm, 120)),
            horizontalOffsetMm  : na_number(config.glazebar_horizontal_offset_mm, 0),
            horizontalOffsetsMm : na_collect_bar_offsets(config, 'glazebar_h_offset_', horizontalBars),
            verticalOffsetsMm   : na_collect_bar_offsets(config, 'glazebar_v_offset_', verticalBars)
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Opening / Panel Placement
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve Opening Inner Clear Dimensions and Panel Grid
    // ------------------------------------------------------------
    function na_opening(config) {
        config = config || {};
        const width  = Math.max(800, na_number(config.width_mm, 3600));
        const height = Math.max(1500, na_number(config.height_mm, 2100));
        const uniform = Math.max(0, na_number(config.frame_thickness_mm, 50));
        const advanced = na_boolean(config.advanced_frame_controls, false);

        function na_edge(key) {
            return advanced ? Math.max(0, na_number(config[key], uniform)) : uniform;
        }

        const left   = na_edge('frame_left_thickness_mm');
        const right  = na_edge('frame_right_thickness_mm');
        const top    = na_edge('frame_top_thickness_mm');
        const bottom = na_edge('frame_bottom_thickness_mm');
        const panelCount = Math.max(2, Math.min(8, Math.round(na_number(config.bifold_door_panel_count, 4))));
        const innerWidth  = Math.max(0, width - left - right);
        const innerHeight = Math.max(0, height - top - bottom);
        const panelWidth  = panelCount > 0 ? innerWidth / panelCount : 0;

        return {
            widthMm       : width,
            heightMm      : height,
            frameLeftMm   : left,
            frameRightMm  : right,
            frameTopMm    : top,
            frameBottomMm : bottom,
            innerLeftMm   : left,
            innerBottomMm : bottom,
            innerWidthMm  : innerWidth,
            innerHeightMm : innerHeight,
            panelCount    : panelCount,
            panelWidthMm  : panelWidth,
            panelGapMm    : PANEL_GAP_MM
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Fielded Panel Layout
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Build Field Cell Grid from Preset or Custom Counts
    // ------------------------------------------------------------
    function na_field_cells(region, settings, separatorSource) {
        if (!region || region.widthMm <= 0 || region.heightMm <= 0) return [];

        const grid = settings.preset === 'Custom'
            ? [Math.round(settings.columns), Math.round(settings.rows)]
            : (NA_PRESETS[settings.preset] || [1, 1]);
        const columns   = grid[0];
        const rows      = grid[1];
        const separator = Math.max(30, separatorSource * 0.55);
        const width     = (region.widthMm - separator * (columns - 1)) / columns;
        const height    = (region.heightMm - separator * (rows - 1)) / rows;
        if (width < 40 || height < 40) return [];

        const cells = [];
        for (let row = 0; row < rows; row += 1) {
            for (let column = 0; column < columns; column += 1) {
                cells.push({
                    xMm      : region.xMm + column * (width + separator),
                    zMm      : region.zMm + row * (height + separator),
                    widthMm  : width,
                    heightMm : height
                });
            }
        }
        return cells;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Derive Field Dividers from Cell Gaps
    // ------------------------------------------------------------
    function na_field_dividers(region, cells) {
        if (!region || cells.length < 2) return [];

        const columnsByX = new Map();
        const rowsByZ = new Map();
        cells.forEach(function (cell) {
            if (!columnsByX.has(cell.xMm)) columnsByX.set(cell.xMm, cell);
            if (!rowsByZ.has(cell.zMm)) rowsByZ.set(cell.zMm, cell);
        });

        const columns = Array.from(columnsByX.values()).sort(function (a, b) { return a.xMm - b.xMm; });
        const rows = Array.from(rowsByZ.values()).sort(function (a, b) { return a.zMm - b.zMm; });
        const dividers = [];

        for (let column = 0; column < columns.length - 1; column += 1) {
            const current = columns[column];
            const following = columns[column + 1];
            const gapX = current.xMm + current.widthMm;
            const gapWidth = following.xMm - gapX;
            if (gapWidth > 0) {
                dividers.push({
                    orientation : 'vertical',
                    index       : column + 1,
                    xMm         : gapX,
                    zMm         : region.zMm,
                    widthMm     : gapWidth,
                    heightMm    : region.heightMm
                });
            }
        }

        for (let row = 0; row < rows.length - 1; row += 1) {
            const current = rows[row];
            const following = rows[row + 1];
            const gapZ = current.zMm + current.heightMm;
            const gapHeight = following.zMm - gapZ;
            if (gapHeight > 0) {
                dividers.push({
                    orientation : 'horizontal',
                    index       : row + 1,
                    xMm         : region.xMm,
                    zMm         : gapZ,
                    widthMm     : region.widthMm,
                    heightMm    : gapHeight
                });
            }
        }
        return dividers;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Field / Glazed Regions and Cells for One Panel
    // ------------------------------------------------------------
    function na_panel_layout(panel) {
        const settings = panel.settings;
        const stile = na_clamp(settings.stileMm, 20, panel.widthMm / 3);
        const topRail = na_clamp(settings.topRailMm, 20, panel.heightMm / 3);
        const bottomRail = na_clamp(settings.bottomRailMm, 20, panel.heightMm / 3);
        const midRail = na_clamp(settings.midRailMm, 20, panel.heightMm / 3);
        const full = {
            xMm      : panel.originXMm + stile,
            zMm      : panel.originZMm + bottomRail,
            widthMm  : Math.max(0, panel.widthMm - 2 * stile),
            heightMm : Math.max(0, panel.heightMm - topRail - bottomRail)
        };

        let field = null;
        let glazed = null;
        if (settings.composition === 'FullyGlazed') {
            glazed = full;
        } else if (settings.composition === 'FullyFielded') {
            field = full;
        } else {
            const fieldHeight = na_clamp(
                settings.fieldedHeightMm,
                100,
                Math.max(100, full.heightMm - midRail - 100)
            );
            field = Object.assign({}, full, { heightMm: fieldHeight });
            glazed = {
                xMm      : full.xMm,
                zMm      : full.zMm + fieldHeight + midRail,
                widthMm  : full.widthMm,
                heightMm : Math.max(0, full.heightMm - fieldHeight - midRail)
            };
        }

        const fieldCells = na_field_cells(field, settings, midRail);
        return {
            stileMm       : stile,
            topRailMm     : topRail,
            bottomRailMm  : bottomRail,
            midRailMm     : midRail,
            fieldRegion   : field,
            glazedRegion  : glazed,
            fieldCells    : fieldCells,
            fieldDividers : na_field_dividers(field, fieldCells)
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build One Panel Descriptor with Layout
    // ------------------------------------------------------------
    function na_build_panel(opening, settings, index) {
        const originXMm = opening.innerLeftMm + index * opening.panelWidthMm + (opening.panelGapMm / 2);
        const widthMm = Math.max(0, opening.panelWidthMm - opening.panelGapMm);
        const panel = {
            index      : index,
            originXMm  : originXMm,
            originZMm  : opening.innerBottomMm,
            widthMm    : widthMm,
            heightMm   : opening.innerHeightMm,
            settings   : settings
        };
        panel.panelLayout = na_panel_layout(panel);
        return panel;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Public API
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve Full Multifold Panel Layout from Live Config
    // ------------------------------------------------------------
    function na_resolve(config) {
        config = config || {};
        const settings = na_panel_settings(config);
        const opening = na_opening(config);
        const panels = [];
        for (let index = 0; index < opening.panelCount; index += 1) {
            panels.push(na_build_panel(opening, settings, index));
        }
        return {
            settings : settings,
            opening  : opening,
            panels   : panels
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Validate Resolved Layout and Collect User-Facing Errors
    // ------------------------------------------------------------
    function na_validate(config) {
        const resolved = na_resolve(config);
        const errors = [];
        if (resolved.opening.innerWidthMm <= 0 || resolved.opening.innerHeightMm <= 0) {
            errors.push('Clear frame opening must be positive.');
        }
        if (resolved.settings.composition !== 'FullyGlazed') {
            resolved.panels.forEach(function (panel) {
                if (!panel.panelLayout.fieldCells.length) {
                    errors.push('Panel ' + (panel.index + 1) + ' field layout is too small for the selected settings.');
                }
            });
        }
        return { valid: errors.length === 0, errors: errors, resolved: resolved };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    return {
        na_resolve         : na_resolve,
        na_panel_settings  : na_panel_settings,
        na_validate        : na_validate
    };

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtFold__PanelConfigResolver = Object.freeze(Na__ExtFold__PanelConfigResolver);

console.log('[NA_EXT_FOLD] PanelConfigResolver loaded.');

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
