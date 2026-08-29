/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOUBLE DOOR - ELEVATION SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDouble__Viewport__ElevationGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Renders a 2D elevation SVG of the exterior double door for the
                live preview viewport. Draws frame, both leaves (fielded panels
                + glazed regions), glaze bars, leaded glass, handles, and
                optional overall / per-leaf dimension labels.

   DESCRIPTION:
   - Thin adapter over the shared ExtDoorCommon elevation generator factory:
     the whole drawing pipeline lives there so the Double Door and the Single
     Door render from one code path. Only the key prefix and the handle
     visibility rule are supplied here.
   - Layout is resolved via Na__ExtDouble__LeafConfigResolver so the SVG
     matches the Ruby 3D builder and the DXF exporter.

   DEPENDENCIES:
   - @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__Viewport__ElevationGenerator__.js
   - window.Na__ExtDouble__LeafConfigResolver.na_resolve

   ============================================================================= */


// =============================================================================
// REGION | ExtDouble Elevation SVG Generator Module
// =============================================================================

const Na__ExtDouble__ElevationGenerator = (function () {

    'use strict';

    const na_boolean = window.Na__ExtDoorCommon__ElevationGenerator.na_boolean;

    // HELPER FUNCTION | Decide Whether One Leaf Carries a Drawn Handle
    // ------------------------------------------------------------
    // Fixed panels carry no ironmongery, so no handle is drawn at all.
    // Otherwise the passive leaf only gets one when handles are paired.
    function na_draw_handle_for_leaf(config, leaf) {
        if (na_boolean(config.double_door_fixed_panels, false)) return false;
        const handlePaired = String(config.double_door_handle_pairing || 'Paired').toLowerCase() === 'paired';
        return leaf.isActive || handlePaired;
    }
    // ---------------------------------------------------------------

    return window.Na__ExtDoorCommon__ElevationGenerator.na_create({
        prefix                  : 'double_door',
        na_resolver             : function () { return window.Na__ExtDouble__LeafConfigResolver; },
        na_draw_handle_for_leaf : na_draw_handle_for_leaf
    });

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtDouble__ElevationGenerator = Object.freeze(Na__ExtDouble__ElevationGenerator);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
