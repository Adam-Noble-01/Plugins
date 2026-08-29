/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - LEAF CONFIG RESOLVER
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSingleDoor__UiSystem__LeafConfigResolver__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Resolve opening / frame / leaf geometry and fielded-panel
                settings from the live single-door UI config. Shared by the
                elevation/plan SVG generators, DXF exporter, and validation.
   CREATED    : 29-Aug-2026

   DESCRIPTION:
   - Thin adapter over the shared ExtDoorCommon resolver factory - the same
     factory the Exterior Double Door uses - so the two products resolve panel
     composition, fielded cells, rails and glaze bars through one code path.
   - One leaf spanning the full clear width. The hinge side comes from
     `single_door_swing_side`, so a left-hung leaf latches on the right and a
     right-hung leaf latches on the left, exactly as the Ruby
     ExtSingleDoor LeafLayoutResolver resolves it for the 3D build.
   - There are no per-leaf overrides on a single door: every settings key is
     read straight off the shared `single_door_*` key.

   DEPENDENCIES:
   - @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__UiSystem__LeafConfigResolver__.js
   - Consumed by Na__ExtSingleDoor__ElevationGenerator, PlanGenerator,
     DxfExporter, and Na__Viewport__Validation.

   ============================================================================= */


// =============================================================================
// REGION | ExtSingleDoor Leaf Config Resolver Module
// =============================================================================

const Na__ExtSingleDoor__LeafConfigResolver = (function () {

    'use strict';


    // -----------------------------------------------------------------------------
    // REGION | Constants + Shared Helpers
    // -----------------------------------------------------------------------------

    const NA_MIN_LEAF_WIDTH_MM = 300;                                                     // <-- Minimum clear leaf width
    const NA_PREFIX            = 'single_door';

    const Shared    = window.Na__ExtDoorCommon__LeafConfigResolver;
    const na_number = Shared.na_number;

    // endregion -------------------------------------------------------------------


    // -----------------------------------------------------------------------------
    // REGION | Single-Door Specific Spec Hooks
    // -----------------------------------------------------------------------------

    // FUNCTION | Build the One Leaf Slot Spanning the Full Clear Width
    // ------------------------------------------------------------
    // `single_door_swing_side` names the HINGE stile. A left-hung leaf pivots
    // on the left jamb and latches on the right; a right-hung leaf is the
    // mirror. `closedLatchAngleDeg` is the plan-space bearing of the closed
    // latch edge measured from the pivot, matching the double door's left/right
    // leaf convention so the shared swing-arc maths is identical.
    function na_leaf_slots(config, dimensions) {
        const leftHung = !String(config.single_door_swing_side || 'Left').toLowerCase().startsWith('r');
        const originX  = dimensions.innerXMm;
        const width    = dimensions.innerWidthMm;

        return [{
            index               : 1,
            side                : leftHung ? 'left' : 'right',
            sideName            : leftHung ? 'Left' : 'Right',
            settingsSide        : null,
            isActive            : true,
            originXMm           : originX,
            widthMm             : width,
            hingeXMm            : leftHung ? originX : originX + width,
            latchXMm            : leftHung ? originX + width : originX,
            closedLatchAngleDeg : leftHung ? 0 : 180,
            openingAngleDeg     : na_number(config.single_door_opening_angle_deg, 90),
            hingeProjectionMm   : na_number(config.single_door_hinge_projection_mm, 0)
        }];
    }
    // ---------------------------------------------------------------

    // FUNCTION | Settings Reader (Shared Keys Only - No Per-Leaf Overrides)
    // ------------------------------------------------------------
    function na_value_factory(config) {
        return function na_value(suffix, fallback) {
            const sharedKey = NA_PREFIX + '_' + suffix;
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
        defaultWidthMm   : 1000,
        defaultHeightMm  : 2100,
        minLeafWidthMm   : NA_MIN_LEAF_WIDTH_MM,
        minLeafCount     : 1,
        minWidthMessage  : 'Clear frame width must accommodate a 300 mm leaf.',
        na_leaf_slots    : na_leaf_slots,
        na_value_factory : na_value_factory
    });

    // endregion -------------------------------------------------------------------


    return {
        na_resolve              : Resolver.na_resolve,
        na_effective_leaf_config: Resolver.na_effective_leaf_config,
        na_validate             : Resolver.na_validate
    };

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtSingleDoor__LeafConfigResolver = Object.freeze(Na__ExtSingleDoor__LeafConfigResolver);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
