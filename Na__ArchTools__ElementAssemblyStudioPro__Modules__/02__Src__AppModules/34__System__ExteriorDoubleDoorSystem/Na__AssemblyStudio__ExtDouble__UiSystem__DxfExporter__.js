/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOUBLE DOOR - DXF EXPORTER (UI)
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtDouble__UiSystem__DxfExporter__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Build a lightweight DXF entity stream (elevation + plan) for
                the exterior double door from the live UI config. Used by the
                WindowSystem DXF download path when double_door_mode is active.

   DESCRIPTION:
   - Thin adapter over the shared ExtDoorCommon DXF exporter factory, so the
     Double Door and the Single Door emit the same layers and geometry.
   - Layout is resolved via Na__ExtDouble__LeafConfigResolver so DXF geometry
     matches the elevation preview and the Ruby 3D builder.

   DEPENDENCIES:
   - @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__UiSystem__DxfExporter__.js
   - window.Na__ExtDouble__LeafConfigResolver.na_resolve

   ============================================================================= */


// =============================================================================
// REGION | ExtDouble DXF Exporter Module
// =============================================================================

const Na__ExtDouble__DxfExporter = window.Na__ExtDoorCommon__DxfExporter.na_create({
    prefix                  : 'double_door',
    productLabel            : 'Exterior Double Door',
    na_resolver             : function () { return window.Na__ExtDouble__LeafConfigResolver; },
    // Only the active leaf carries the exported handle circle.
    na_draw_handle_for_leaf : function (config, leaf) { return leaf.isActive === true; }
});


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtDouble__DxfExporter = Object.freeze(Na__ExtDouble__DxfExporter);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
