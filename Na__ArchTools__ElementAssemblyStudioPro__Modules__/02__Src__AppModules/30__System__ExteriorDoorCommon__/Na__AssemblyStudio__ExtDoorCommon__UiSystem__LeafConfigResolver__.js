/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - LEAF CONFIG RESOLVER
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDoorCommon__UiSystem__LeafConfigResolver__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Prefix-parameterised resolver factory shared by every exterior
                door product that is built from hinged leaves. Resolves the
                opening / frame box, the effective per-leaf panel + glazebar
                settings, and the fielded-panel layout for each leaf.
   CREATED    : 29-Aug-2026

   DESCRIPTION:
   - Extracted verbatim from the Exterior Double Door resolver so the double
     door and the single door cannot drift apart. Everything that differs
     between the two products is supplied by the caller as a spec hook.
   - `na_create(spec)` returns a resolver object with the same public shape the
     Double Door resolver has always had:
         na_resolve(config)               -> { dimensions, leaves }
         na_effective_leaf_config(cfg, s) -> settings hash for one leaf
         na_validate(config)              -> { valid, errors, resolved }

   SPEC CONTRACT:
     prefix            {string}   Key prefix, no trailing underscore
                                  ('double_door' | 'single_door').
     defaultWidthMm    {number}   width_mm fallback for this product.
     defaultHeightMm   {number}   height_mm fallback for this product.
     minLeafWidthMm    {number}   Minimum clear leaf width (default 300).
     minLeafCount      {number}   Leaves the clear width must accommodate.
     minWidthMessage   {string}   Validation message when the clear width is
                                  below minLeafCount * minLeafWidthMm.
     na_leaf_slots     {function} (config, dimensions) -> [slot]. One slot per
                                  leaf: index, side, sideName, isActive,
                                  originXMm, widthMm, hingeXMm, latchXMm,
                                  closedLatchAngleDeg, openingAngleDeg,
                                  hingeProjectionMm, settingsSide.
     na_value_factory  {function} (config, settingsSide) -> (suffix, fallback).
                                  Resolves one settings key for one leaf, so a
                                  product with per-leaf overrides can layer them
                                  over the shared keys.

   DEPENDENCIES:
   - Consumed by Na__ExtDouble__LeafConfigResolver and
     Na__ExtSingleDoor__LeafConfigResolver.

   ============================================================================= */


// =============================================================================
// REGION | ExtDoorCommon Leaf Config Resolver Factory
// =============================================================================

const Na__ExtDoorCommon__LeafConfigResolver = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | Constants
    // -----------------------------------------------------------------------------

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
    // REGION | Fielded Panel Layout (Product Independent)
    // -----------------------------------------------------------------------------

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

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Resolver Factory
    // -----------------------------------------------------------------------------

    // FUNCTION | Build a Prefix-Bound Leaf Config Resolver
    // ------------------------------------------------------------
    function na_create(spec) {
        const prefix          = String(spec.prefix);
        const defaultWidthMm  = na_number(spec.defaultWidthMm, 1900);
        const defaultHeightMm = na_number(spec.defaultHeightMm, 2100);
        const minLeafWidthMm  = na_number(spec.minLeafWidthMm, 300);
        const minLeafCount    = Math.max(1, Math.round(na_number(spec.minLeafCount, 1)));
        const minWidthMessage = spec.minWidthMessage ||
            ('Clear frame width must be at least ' + (minLeafCount * minLeafWidthMm) + ' mm.');

        // HELPER FUNCTION | Read One Prefixed Config Key
        // ------------------------------------------------------------
        function na_key(suffix) {
            return prefix + '_' + suffix;
        }
        // ---------------------------------------------------------------

        // FUNCTION | Resolve Opening and Frame Edge Dimensions (mm)
        // ------------------------------------------------------------
        function na_dimensions(config) {
            const width    = Math.max(0, na_number(config.width_mm, defaultWidthMm));
            const height   = Math.max(0, na_number(config.height_mm, defaultHeightMm));
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

        // HELPER FUNCTION | Collect Per-Bar Offset Array for One Axis
        // ------------------------------------------------------------
        // Same shared -> per-leaf -> plain-window key resolution as scalars;
        // bars beyond the slider pool (doors allow up to 12) get 0.
        function na_collect_leaf_bar_offsets(na_value, config, barPrefix, count) {
            const offsets = [];
            for (let barIndex = 1; barIndex <= count; barIndex += 1) {
                const suffix = barPrefix + barIndex + '_mm';
                offsets.push(na_number(na_value(suffix, config[suffix]), 0));
            }
            return offsets;
        }
        // ---------------------------------------------------------------

        // FUNCTION | Resolve Effective Panel / Glazebar Settings for One Leaf
        // ------------------------------------------------------------
        function na_effective_leaf_config(config, settingsSide) {
            const na_value = spec.na_value_factory(config || {}, settingsSide);

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

        // HELPER FUNCTION | Signed Opening Angle from Hinge Side + Swing Direction
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
            const thickness = Math.max(1, na_number(config[na_key('leaf_thickness_mm')], 50));
            const direction = String(config[na_key('swing_direction')] || 'Inward').toLowerCase();
            return direction === 'outward'
                ? dimensions.frameInsetMm + dimensions.frameDepthMm - thickness
                : dimensions.frameInsetMm;
        }
        // ---------------------------------------------------------------

        // HELPER FUNCTION | Hinge Pivot Y Including Projection
        // ------------------------------------------------------------
        function na_pivot_y(config, dimensions, projection) {
            const direction = String(config[na_key('swing_direction')] || 'Inward').toLowerCase();
            return direction === 'outward'
                ? dimensions.frameInsetMm + dimensions.frameDepthMm + projection
                : dimensions.frameInsetMm - projection;
        }
        // ---------------------------------------------------------------

        // FUNCTION | Build One Resolved Leaf Descriptor from a Product Slot
        // ------------------------------------------------------------
        function na_leaf(config, dimensions, slot) {
            const projection    = na_clamp(slot.hingeProjectionMm, 0, 150);
            const angle         = na_clamp(slot.openingAngleDeg, 0, 180);
            const settings      = na_effective_leaf_config(config, slot.settingsSide);
            const leafThickness = Math.max(1, na_number(config[na_key('leaf_thickness_mm')], 50));

            settings.glazeBarInsetMm = na_clamp(
                settings.glazeBarInsetMm,
                0,
                Math.max(0, leafThickness / 2 - 1)
            );

            const leaf = {
                index              : slot.index,
                side               : slot.side,
                sideName           : slot.sideName,
                isActive           : slot.isActive === true,
                originXMm          : slot.originXMm,
                originYMm          : na_panel_y(config, dimensions),
                originZMm          : dimensions.innerZMm,
                widthMm            : slot.widthMm,
                heightMm           : dimensions.innerHeightMm,
                thicknessMm        : leafThickness,
                hingeXMm           : slot.hingeXMm,
                latchXMm           : slot.latchXMm,
                pivotYMm           : na_pivot_y(config, dimensions, projection),
                hingeProjectionMm  : projection,
                openingAngleDeg    : angle,
                signedAngleDeg     : na_signed_angle(slot.side, config[na_key('swing_direction')] || 'Inward', angle),
                closedLatchAngleDeg: slot.closedLatchAngleDeg,
                settings           : settings
            };
            leaf.panelLayout = na_panel_layout(leaf);
            return leaf;
        }
        // ---------------------------------------------------------------

        // FUNCTION | Resolve Full Door Layout from Live Config
        // ------------------------------------------------------------
        function na_resolve(config) {
            config = config || {};
            const dimensions = na_dimensions(config);
            const slots      = spec.na_leaf_slots(config, dimensions, {
                na_number  : na_number,
                na_boolean : na_boolean,
                na_clamp   : na_clamp,
                minLeafWidthMm : minLeafWidthMm
            }) || [];

            return {
                dimensions : dimensions,
                leaves     : slots.map(function (slot) {
                    return na_leaf(config, dimensions, slot);
                })
            };
        }
        // ---------------------------------------------------------------

        // FUNCTION | Validate Resolved Layout and Collect User-Facing Errors
        // ------------------------------------------------------------
        function na_validate(config) {
            const resolved = na_resolve(config);
            const errors   = [];

            if (resolved.dimensions.innerWidthMm < minLeafCount * minLeafWidthMm) {
                errors.push(minWidthMessage);
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

        return {
            na_resolve               : na_resolve,
            na_effective_leaf_config : na_effective_leaf_config,
            na_validate              : na_validate,
            na_dimensions            : na_dimensions
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    return {
        na_create   : na_create,
        na_presets  : NA_PRESETS,
        na_number   : na_number,
        na_boolean  : na_boolean,
        na_clamp    : na_clamp
    };

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtDoorCommon__LeafConfigResolver = Object.freeze(Na__ExtDoorCommon__LeafConfigResolver);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
