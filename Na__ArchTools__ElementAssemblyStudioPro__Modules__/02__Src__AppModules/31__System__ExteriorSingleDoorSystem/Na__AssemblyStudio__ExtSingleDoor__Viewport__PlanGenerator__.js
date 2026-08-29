/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - PLAN SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSingleDoor__Viewport__PlanGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Renders the 2D plan SVG of the exterior single door - reveal
                walls, frame jambs, the leaf footprint, open-state ghost, hinge
                pivot, swing arc and handle schematic.
   CREATED    : 29-Aug-2026

   DESCRIPTION:
   - Thin adapter over the shared ExtDoorCommon plan generator factory, the
     same factory the Exterior Double Door uses.

   DEPENDENCIES:
   - @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__Viewport__PlanGenerator__.js
   - window.Na__ExtSingleDoor__LeafConfigResolver.na_resolve

   ============================================================================= */


(function () {
    'use strict';

    // HELPER FUNCTION | Decide Whether the Leaf Carries a Drawn Handle
    // ------------------------------------------------------------
    // The fixed-panel case is handled by the shared drawer (it returns before
    // the handle stage), so an opening single door always gets its handle.
    function na_draw_handle_for_leaf() {
        return true;
    }
    // ---------------------------------------------------------------

    window.Na__ExtSingleDoor__PlanGenerator = Object.freeze(
        window.Na__ExtDoorCommon__PlanGenerator.na_create({
            prefix                  : 'single_door',
            na_resolver             : function () { return window.Na__ExtSingleDoor__LeafConfigResolver; },
            na_draw_handle_for_leaf : na_draw_handle_for_leaf
        })
    );
}());


/* =============================================================================
   END OF FILE
   ============================================================================= */
