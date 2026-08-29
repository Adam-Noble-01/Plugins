/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - ELEVATION SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSingleDoor__Viewport__ElevationGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Renders a 2D elevation SVG of the exterior single door for the
                live preview viewport - frame, the leaf with its fielded panels
                and glazed region, glaze bars, leaded glass, handle and the
                dimension labels.
   CREATED    : 29-Aug-2026

   DESCRIPTION:
   - Thin adapter over the shared ExtDoorCommon elevation generator factory,
     the same factory the Exterior Double Door uses. This replaces the old
     behaviour where a single exterior door fell through to the WindowSystem
     casement generator and drew as a plain window.

   DEPENDENCIES:
   - @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__Viewport__ElevationGenerator__.js
   - window.Na__ExtSingleDoor__LeafConfigResolver.na_resolve

   ============================================================================= */


// =============================================================================
// REGION | ExtSingleDoor Elevation SVG Generator Module
// =============================================================================

const Na__ExtSingleDoor__ElevationGenerator = (function () {

    'use strict';

    const na_boolean = window.Na__ExtDoorCommon__ElevationGenerator.na_boolean;

    // HELPER FUNCTION | Decide Whether the Leaf Carries a Drawn Handle
    // ------------------------------------------------------------
    // A fixed panel is dead joinery and carries no ironmongery at all.
    // Every other single door has exactly one handle on its only leaf.
    function na_draw_handle_for_leaf(config) {
        return !na_boolean(config.single_door_fixed_panels, false);
    }
    // ---------------------------------------------------------------

    return window.Na__ExtDoorCommon__ElevationGenerator.na_create({
        prefix                  : 'single_door',
        na_resolver             : function () { return window.Na__ExtSingleDoor__LeafConfigResolver; },
        na_draw_handle_for_leaf : na_draw_handle_for_leaf
    });

})();


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtSingleDoor__ElevationGenerator = Object.freeze(Na__ExtSingleDoor__ElevationGenerator);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
