/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOUBLE DOOR - PLAN SVG GENERATOR
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDouble__Viewport__PlanGenerator__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Renders the 2D plan SVG of the exterior double door - reveal
                walls, frame jambs, both leaf footprints, open-state ghosts,
                hinge pivots, swing arcs and handle schematics.

   DESCRIPTION:
   - Thin adapter over the shared ExtDoorCommon plan generator factory, so the
     Double Door and the Single Door draw from one code path.

   DEPENDENCIES:
   - @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__Viewport__PlanGenerator__.js
   - window.Na__ExtDouble__LeafConfigResolver.na_resolve

   ============================================================================= */


(function () {
    'use strict';

    // HELPER FUNCTION | Decide Whether One Leaf Carries a Drawn Handle
    // ------------------------------------------------------------
    // The fixed-panel case is handled by the shared drawer (it returns before
    // the handle stage), so this only decides active-versus-paired.
    function na_draw_handle_for_leaf(config, leaf) {
        var handlePaired = String((config && config.double_door_handle_pairing) || 'Paired').toLowerCase() === 'paired';
        return leaf.isActive || handlePaired;
    }
    // ---------------------------------------------------------------

    window.Na__ExtDouble__PlanGenerator = Object.freeze(
        window.Na__ExtDoorCommon__PlanGenerator.na_create({
            prefix                  : 'double_door',
            na_resolver             : function () { return window.Na__ExtDouble__LeafConfigResolver; },
            na_draw_handle_for_leaf : na_draw_handle_for_leaf
        })
    );
}());


/* =============================================================================
   END OF FILE
   ============================================================================= */
