/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOUBLE DOOR - LEAF CONFIG RESOLVER
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDouble__UiSystem__LeafConfigResolver__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Resolve opening / frame / leaf geometry and per-leaf panel
                settings from the live double-door UI config. Shared by the
                elevation/plan SVG generators, DXF exporter, and validation.

   DESCRIPTION:
   - Thin adapter over the shared ExtDoorCommon resolver factory. Everything
     generic (frame box, effective leaf settings, fielded panel layout,
     validation) lives in the shared module so the Double Door and the
     Single Door cannot drift apart; only the two-leaf split and the per-leaf
     override rules are supplied here.
   - Reads shared window-level keys (width_mm, height_mm, frame_*_thickness_mm)
     plus double_door_* leaf / panel / glazebar keys.
   - Supports linked leaf settings or per-leaf overrides when
     double_door_leaf_settings_linked is false and the side override flag
     is enabled.
   - Active leaf width supports EQ (50/50) or an absolute mm value clamped
     so both leaves keep the 300 mm minimum.

   DEPENDENCIES:
   - @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__UiSystem__LeafConfigResolver__.js
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
    // REGION | Constants + Shared Helpers
    // -----------------------------------------------------------------------------

    const NA_MIN_LEAF_WIDTH_MM = 300;                                                     // <-- Minimum clear leaf width
    const NA_PREFIX            = 'double_door';

    const Shared = window.Na__ExtDoorCommon__LeafConfigResolver;
    const na_number  = Shared.na_number;
    const na_boolean = Shared.na_boolean;
    const na_clamp   = Shared.na_clamp;

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Double-Door Specific Spec Hooks
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

    // FUNCTION | Build the Two Leaf Slots (Left + Right) for One Opening
    // ------------------------------------------------------------
    function na_leaf_slots(config, dimensions) {
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

        return ['left', 'right'].map(function (side) {
            const left    = side === 'left';
            const width   = left ? widths.left : widths.right;
            const originX = left ? dimensions.innerXMm : dimensions.innerXMm + widths.left;
            return {
                index               : left ? 1 : 2,
                side                : side,
                sideName            : left ? 'Left' : 'Right',
                settingsSide        : side,
                isActive            : activeSide === side,
                originXMm           : originX,
                widthMm             : width,
                hingeXMm            : left ? dimensions.innerXMm : dimensions.innerXMm + dimensions.innerWidthMm,
                latchXMm            : left ? originX + width : originX,
                closedLatchAngleDeg : left ? 0 : 180,
                openingAngleDeg     : config['double_door_' + side + '_opening_angle_deg'],
                hingeProjectionMm   : config['double_door_' + side + '_hinge_projection_mm']
            };
        });
    }
    // ---------------------------------------------------------------

    // FUNCTION | Per-Leaf Settings Reader (Linked / Override Aware)
    // ------------------------------------------------------------
    function na_value_factory(config, settingsSide) {
        const sidePrefix = NA_PREFIX + '_' + settingsSide + '_';
        const linked     = na_boolean(config.double_door_leaf_settings_linked, true);
        const override   = na_boolean(config[sidePrefix + 'leaf_override_enabled'], false);

        return function na_value(suffix, fallback) {
            const sharedKey = NA_PREFIX + '_' + suffix;
            const leafKey   = sidePrefix + suffix;
            if (!linked && override && config[leafKey] !== undefined) return config[leafKey];
            return config[sharedKey] !== undefined ? config[sharedKey] : fallback;
        };
    }
    // ---------------------------------------------------------------

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Bound Resolver
    // -----------------------------------------------------------------------------

    // @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__UiSystem__LeafConfigResolver__.js
    const Resolver = Shared.na_create({
        prefix           : NA_PREFIX,
        defaultWidthMm   : 1900,
        defaultHeightMm  : 2100,
        minLeafWidthMm   : NA_MIN_LEAF_WIDTH_MM,
        minLeafCount     : 2,
        minWidthMessage  : 'Clear frame width must accommodate two 300 mm leaves.',
        na_leaf_slots    : na_leaf_slots,
        na_value_factory : na_value_factory
    });

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Public Seed
    // -----------------------------------------------------------------------------

    // FUNCTION | Seed Per-Leaf Override Keys from Current Effective Settings
    // ------------------------------------------------------------
    function na_seed_leaf_override(config, side) {
        const result = Object.assign({}, config || {});
        const source = Resolver.na_effective_leaf_config(result, side);
        const prefix = NA_PREFIX + '_' + side + '_';
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

    // endregion -------------------------------------------------------------------


    return {
        na_resolve              : Resolver.na_resolve,
        na_effective_leaf_config: Resolver.na_effective_leaf_config,
        na_seed_leaf_override   : na_seed_leaf_override,
        na_validate             : Resolver.na_validate
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
