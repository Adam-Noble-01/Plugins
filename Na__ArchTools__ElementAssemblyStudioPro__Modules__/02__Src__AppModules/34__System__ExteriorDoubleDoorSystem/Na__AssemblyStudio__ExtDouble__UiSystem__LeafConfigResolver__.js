/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOUBLE DOOR - LEAF CONFIG RESOLVER
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDouble__UiSystem__LeafConfigResolver__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Resolve opening / frame / leaf geometry and per-leaf panel
                settings from the live double-door UI config. Shared by the
                elevation/plan SVG generators, DXF exporter, and validation.

   DESCRIPTION:
   - Reads shared window-level keys (width_mm, height_mm, frame_*_thickness_mm)
     plus double_door_* leaf / panel / glazebar keys.
   - Supports linked leaf settings or per-leaf overrides when
     double_door_leaf_settings_linked is false and the side override flag
     is enabled.
   - Active leaf width supports EQ (50/50) or an absolute mm value clamped
     so both leaves keep the 300 mm minimum.

   DEPENDENCIES:
   - Consumed by Na__ExtDouble__ElevationGenerator, PlanGenerator, DxfExporter.
   - WindowSystem MainUiLogic seeds per-leaf overrides via
     na_seed_leaf_override.

   ============================================================================= */


// =============================================================================
// REGION | ExtDouble Leaf Config Resolver Module
// =============================================================================

const Na__ExtDouble__LeafConfigResolver = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | Constants
    // -----------------------------------------------------------------------------

    const NA_MIN_LEAF_WIDTH_MM = 300;                                                     // <-- Minimum clear leaf width
    const NA_PRESETS = {
        OnePanel      : [1, 1],
        TwoVertical   : [2, 1],
        TwoHorizontal : [1, 2],
        FourPanel     : [2, 2],
        SixPanel      : [2, 3]
    };

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Scalar Helpers
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Coerce to Finite Number or Fallback
    // ------------------------------------------------------------
    function na_number(value, fallback) {
        const number = Number(value);
        return Number.isFinite(number) ? number : fallback;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Coerce to Boolean or Fallback
    // ------------------------------------------------------------
    function na_boolean(value, fallback) {
        if (value === undefined || value === null) return fallback;
        return value === true || String(value).toLowerCase() === 'true';
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Clamp Number Between Minimum and Maximum
    // ------------------------------------------------------------
    function na_clamp(value, minimum, maximum) {
        return Math.min(maximum, Math.max(minimum, na_number(value, minimum)));
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Frame / Opening Dimensions
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve Opening and Frame Edge Dimensions (mm)
    // ------------------------------------------------------------
    function na_dimensions(config) {
        const width    = Math.max(0, na_number(config.width_mm, 1900));
        const height   = Math.max(0, na_number(config.height_mm, 2100));
        const uniform  = Math.max(0, na_number(config.frame_thickness_mm, 50));
        const advanced = na_boolean(config.advanced_frame_controls, false);

        function na_edge(key) {
            return advanced ? Math.max(0, na_number(config[key], uniform)) : uniform;
        }

        const left   = na_edge('frame_left_thickness_mm');
        const right  = na_edge('frame_right_thickness_mm');
        const top    = na_edge('frame_top_thickness_mm');
        const bottom = na_edge('frame_bottom_thickness_mm');

        return {
            widthMm       : width,
            heightMm      : height,
            frameLeftMm   : left,
            frameRightMm  : right,
            frameTopMm    : top,
            frameBottomMm : bottom,
            frameDepthMm  : Math.max(1, na_number(config.frame_depth_mm, 70)),
            frameInsetMm  : na_number(config.frame_wall_inset_mm, 0),
            innerXMm      : left,
            innerZMm      : bottom,
            innerWidthMm  : Math.max(0, width - left - right),
            innerHeightMm : Math.max(0, height - top - bottom)
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Per-Leaf Settings Resolution
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Collect Per-Bar Offset Array for One Axis
    // ------------------------------------------------------------
    // Same shared -> per-leaf -> plain-window key resolution as scalars;
    // bars beyond the slider pool (doors allow up to 12) get 0.
    function na_collect_leaf_bar_offsets(na_value, config, prefix, count) {
        const offsets = [];
        for (let barIndex = 1; barIndex <= count; barIndex += 1) {
            const suffix = prefix + barIndex + '_mm';
            offsets.push(na_number(na_value(suffix, config[suffix]), 0));
        }
        return offsets;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Effective Panel / Glazebar Settings for One Side
    // ------------------------------------------------------------
    function na_effective_leaf_config(config, side) {
        const sidePrefix = 'double_door_' + side + '_';
        const linked     = na_boolean(config.double_door_leaf_settings_linked, true);
        const override   = na_boolean(config[sidePrefix + 'leaf_override_enabled'], false);

        function na_value(suffix, fallback) {
            const sharedKey = 'double_door_' + suffix;
            const leafKey   = sidePrefix + suffix;
            if (!linked && override && config[leafKey] !== undefined) return config[leafKey];
            return config[sharedKey] !== undefined ? config[sharedKey] : fallback;
        }

        const legacyRailMm   = na_number(na_value('panel_rail_width_mm', 150), 150);
        const horizontalBars = na_clamp(na_value('horizontal_glaze_bars', config.horizontal_glaze_bars || 0), 0, 12);
        const verticalBars   = na_clamp(na_value('vertical_glaze_bars', config.vertical_glaze_bars || 0), 0, 12);

        return {
            composition          : na_value('leaf_composition', 'GlazedOverFielded'),
            outputMode           : na_value('panel_output_mode', 'ThreeDimensional'),
            profile              : na_value('panel_profile', 'RaisedBevelled'),
            preset               : na_value('panel_preset', 'OnePanel'),
            columns              : na_clamp(na_value('panel_columns', 1), 1, 6),
            rows                 : na_clamp(na_value('panel_rows', 1), 1, 6),
            fieldedHeightMm      : na_number(na_value('fielded_section_height_mm', 300), 300),
            midRailMm            : na_number(na_value('mid_rail_width_mm', 120), 120),
            stileMm              : na_number(na_value('panel_stile_width_mm', 95), 95),
            topRailMm            : na_number(na_value('panel_top_rail_width_mm', 95), 95),
            bottomRailMm         : na_number(na_value('panel_bottom_rail_width_mm', legacyRailMm), legacyRailMm),
            insetMm              : na_number(na_value('panel_inset_mm', 25), 25),
            depthMm              : na_number(na_value('panel_depth_mm', 12), 12),
            bevelMm              : na_number(na_value('panel_bevel_width_mm', 18), 18),
            horizontalBars       : horizontalBars,
            verticalBars         : verticalBars,
            glazeBarWidthMm      : na_clamp(na_value('glaze_bar_width_mm', config.glaze_bar_width_mm || 25), 5, 100),
            glazeBarInsetMm      : na_clamp(na_value('glazebar_inset_mm', config.glazebar_inset_mm || 10), 0, 100),
            marginEnabled        : na_boolean(na_value('glazebar_margin_enabled', config.glazebar_margin_enabled), false),
            marginOffsetMm       : Math.max(0, na_number(
                na_value('glazebar_margin_offset_mm', config.glazebar_margin_offset_mm || 120),
                120
            )),
            horizontalOffsetMm   : na_number(
                na_value('glazebar_horizontal_offset_mm', config.glazebar_horizontal_offset_mm || 0),
                0
            ),
            horizontalOffsetsMm  : na_collect_leaf_bar_offsets(na_value, config, 'glazebar_h_offset_', horizontalBars),
            verticalOffsetsMm    : na_collect_leaf_bar_offsets(na_value, config, 'glazebar_v_offset_', verticalBars)
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Leaf Geometry / Swing
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Signed Opening Angle from Side + Swing Direction
    // ------------------------------------------------------------
    function na_signed_angle(side, direction, angle) {
        const hingeSign     = side === 'left' ? 1 : -1;
        const directionSign = String(direction).toLowerCase() === 'inward' ? -1 : 1;
        return hingeSign * directionSign * na_clamp(angle, 0, 180);
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Leaf Origin Y in Frame Depth (Closed Position)
    // ------------------------------------------------------------
    function na_panel_y(config, dimensions) {
        const thickness = Math.max(1, na_number(config.double_door_leaf_thickness_mm, 50));
        const direction = String(config.double_door_swing_direction || 'Inward').toLowerCase();
        return direction === 'outward'
            ? dimensions.frameInsetMm + dimensions.frameDepthMm - thickness
            : dimensions.frameInsetMm;
    }
    // ---------------------------------------------------------------

    // HELPER FUNCTION | Hinge Pivot Y Including Projection
    // ------------------------------------------------------------
    function na_pivot_y(config, dimensions, projection) {
        const direction = String(config.double_door_swing_direction || 'Inward').toLowerCase();
        return direction === 'outward'
            ? dimensions.frameInsetMm + dimensions.frameDepthMm + projection
            : dimensions.frameInsetMm - projection;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Build One Resolved Leaf Descriptor
    // ------------------------------------------------------------
    function na_leaf(config, dimensions, widths, side) {
        const left          = side === 'left';
        const width         = left ? widths.left : widths.right;
        const originX       = left ? dimensions.innerXMm : dimensions.innerXMm + widths.left;
        const projection    = na_clamp(config['double_door_' + side + '_hinge_projection_mm'], 0, 150);
        const angle         = na_clamp(config['double_door_' + side + '_opening_angle_deg'], 0, 180);
        const settings      = na_effective_leaf_config(config, side);
        const leafThickness = Math.max(1, na_number(config.double_door_leaf_thickness_mm, 50));

        settings.glazeBarInsetMm = na_clamp(
            settings.glazeBarInsetMm,
            0,
            Math.max(0, leafThickness / 2 - 1)
        );

        const leaf = {
            index              : left ? 1 : 2,
            side               : side,
            sideName           : left ? 'Left' : 'Right',
            isActive           : String(config.double_door_active_leaf || 'Left').toLowerCase() === side,
            originXMm          : originX,
            originYMm          : na_panel_y(config, dimensions),
            originZMm          : dimensions.innerZMm,
            widthMm            : width,
            heightMm           : dimensions.innerHeightMm,
            thicknessMm        : leafThickness,
            hingeXMm           : left ? dimensions.innerXMm : dimensions.innerXMm + dimensions.innerWidthMm,
            pivotYMm           : na_pivot_y(config, dimensions, projection),
            hingeProjectionMm  : projection,
            openingAngleDeg    : angle,
            signedAngleDeg     : na_signed_angle(side, config.double_door_swing_direction || 'Inward', angle),
            closedLatchAngleDeg: left ? 0 : 180,
            settings           : settings
        };
        leaf.panelLayout = na_panel_layout(leaf);
        return leaf;
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Fielded Panel Layout
    // -----------------------------------------------------------------------------

    // FUNCTION | Resolve Field / Glazed Regions and Field Cells for One Leaf
    // ------------------------------------------------------------
    function na_panel_layout(leaf) {
        const settings   = leaf.settings;
        const stile      = na_clamp(settings.stileMm, 20, leaf.widthMm / 3);
        const topRail    = na_clamp(settings.topRailMm, 20, leaf.heightMm / 3);
        const bottomRail = na_clamp(settings.bottomRailMm, 20, leaf.heightMm / 3);
        const midRail    = na_clamp(settings.midRailMm, 20, leaf.heightMm / 3);
        const full = {
            xMm      : leaf.originXMm + stile,
            zMm      : leaf.originZMm + bottomRail,
            widthMm  : Math.max(0, leaf.widthMm - 2 * stile),
            heightMm : Math.max(0, leaf.heightMm - topRail - bottomRail)
        };

        let field  = null;
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

    // HELPER FUNCTION | Build Field Cell Grid from Preset or Custom Columns/Rows
    // ------------------------------------------------------------
    function na_field_cells(region, settings, separatorSource) {
        if (!region || region.widthMm <= 0 || region.heightMm <= 0) return [];

        const grid    = settings.preset === 'Custom'
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

    // HELPER FUNCTION | Derive Vertical / Horizontal Field Dividers from Cells
    // ------------------------------------------------------------
    function na_field_dividers(region, cells) {
        if (!region || cells.length < 2) return [];

        const columnsByX = new Map();
        const rowsByZ    = new Map();
        cells.forEach(function (cell) {
            if (!columnsByX.has(cell.xMm)) columnsByX.set(cell.xMm, cell);
            if (!rowsByZ.has(cell.zMm)) rowsByZ.set(cell.zMm, cell);
        });

        const columns = Array.from(columnsByX.values()).sort(function (a, b) { return a.xMm - b.xMm; });
        const rows    = Array.from(rowsByZ.values()).sort(function (a, b) { return a.zMm - b.zMm; });
        const dividers = [];

        for (let column = 0; column < columns.length - 1; column += 1) {
            const currentColumn   = columns[column];
            const followingColumn = columns[column + 1];
            const gapX            = currentColumn.xMm + currentColumn.widthMm;
            const gapWidth        = followingColumn.xMm - gapX;
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
            const currentRow   = rows[row];
            const followingRow = rows[row + 1];
            const gapZ         = currentRow.zMm + currentRow.heightMm;
            const gapHeight    = followingRow.zMm - gapZ;
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

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Public Resolve / Seed / Validate
    // -----------------------------------------------------------------------------

    // HELPER FUNCTION | Resolve Active Leaf Width from EQ / mm Hybrid Field
    // ------------------------------------------------------------
    // 'EQ' (or any non-numeric value) means an equal 50/50 split; a number
    // is the active leaf width in mm, clamped so both leaves keep the
    // 300 mm minimum.
    function na_resolve_active_leaf_width_mm(config, innerWidthMm, minimum, maximum) {
        const raw = config.double_door_active_leaf_width_mm;
        const num = (typeof raw === 'number') ? raw : parseFloat(raw);
        if (!isFinite(num)) return innerWidthMm / 2;
        return na_clamp(num, minimum, maximum);
    }
    // ---------------------------------------------------------------

    // FUNCTION | Resolve Full Double-Door Layout from Live Config
    // ------------------------------------------------------------
    function na_resolve(config) {
        config = config || {};
        const dimensions  = na_dimensions(config);
        const minimum     = Math.min(NA_MIN_LEAF_WIDTH_MM, dimensions.innerWidthMm / 2);
        const maximum     = Math.max(minimum, dimensions.innerWidthMm - minimum);
        const activeWidth = na_resolve_active_leaf_width_mm(
            config, dimensions.innerWidthMm, minimum, maximum
        );
        const activeSide  = String(config.double_door_active_leaf || 'Left').toLowerCase();
        const leftWidth   = activeSide === 'right'
            ? dimensions.innerWidthMm - activeWidth
            : activeWidth;
        const widths = { left: leftWidth, right: dimensions.innerWidthMm - leftWidth };

        return {
            dimensions : dimensions,
            leaves     : [
                na_leaf(config, dimensions, widths, 'left'),
                na_leaf(config, dimensions, widths, 'right')
            ]
        };
    }
    // ---------------------------------------------------------------

    // FUNCTION | Seed Per-Leaf Override Keys from Current Effective Settings
    // ------------------------------------------------------------
    function na_seed_leaf_override(config, side) {
        const result = Object.assign({}, config || {});
        const source = na_effective_leaf_config(result, side);
        const prefix = 'double_door_' + side + '_';
        const mapping = {
            leaf_composition           : 'composition',
            panel_output_mode          : 'outputMode',
            panel_profile              : 'profile',
            panel_preset               : 'preset',
            panel_columns              : 'columns',
            panel_rows                 : 'rows',
            fielded_section_height_mm  : 'fieldedHeightMm',
            mid_rail_width_mm          : 'midRailMm',
            panel_stile_width_mm       : 'stileMm',
            panel_top_rail_width_mm    : 'topRailMm',
            panel_bottom_rail_width_mm : 'bottomRailMm',
            panel_inset_mm             : 'insetMm',
            panel_depth_mm             : 'depthMm',
            panel_bevel_width_mm       : 'bevelMm',
            horizontal_glaze_bars      : 'horizontalBars',
            vertical_glaze_bars        : 'verticalBars',
            glaze_bar_width_mm         : 'glazeBarWidthMm',
            glazebar_inset_mm          : 'glazeBarInsetMm'
        };

        Object.keys(mapping).forEach(function (suffix) {
            result[prefix + suffix] = source[mapping[suffix]];
        });
        for (let barIndex = 1; barIndex <= 8; barIndex += 1) {
            result[prefix + 'glazebar_h_offset_' + barIndex + '_mm'] =
                (source.horizontalOffsetsMm && source.horizontalOffsetsMm[barIndex - 1]) || 0;
            result[prefix + 'glazebar_v_offset_' + barIndex + '_mm'] =
                (source.verticalOffsetsMm && source.verticalOffsetsMm[barIndex - 1]) || 0;
        }
        result[prefix + 'leaf_override_enabled'] = true;
        return result;
    }
    // ---------------------------------------------------------------

    // FUNCTION | Validate Resolved Layout and Collect User-Facing Errors
    // ------------------------------------------------------------
    function na_validate(config) {
        const resolved = na_resolve(config);
        const errors   = [];

        if (resolved.dimensions.innerWidthMm < 2 * NA_MIN_LEAF_WIDTH_MM) {
            errors.push('Clear frame width must accommodate two 300 mm leaves.');
        }
        if (resolved.dimensions.innerHeightMm <= 0) {
            errors.push('Clear frame height must be positive.');
        }
        resolved.leaves.forEach(function (leaf) {
            if (!leaf.panelLayout.fieldCells.length && leaf.settings.composition !== 'FullyGlazed') {
                errors.push(leaf.sideName + ' field layout is too small for the selected settings.');
            }
        });

        return { valid: errors.length === 0, errors: errors, resolved: resolved };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    return {
        na_resolve              : na_resolve,
        na_effective_leaf_config: na_effective_leaf_config,
        na_seed_leaf_override   : na_seed_leaf_override,
        na_validate             : na_validate
    };

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtDouble__LeafConfigResolver = Object.freeze(Na__ExtDouble__LeafConfigResolver);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
