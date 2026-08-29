/* =============================================================================
   ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - DXF EXPORTER (UI)
   =============================================================================

   FILE       : Na__AssemblyStudio__ExtSingleDoor__UiSystem__DxfExporter__.js
   AUTHOR     : Noble Architecture
   PURPOSE    : Build a lightweight DXF entity stream (elevation + plan) for
                the exterior single door from the live UI config. Used by the
                WindowSystem DXF download path when ext_single_door_mode is
                active and SketchUp is not present (browser fallback).
   CREATED    : 29-Aug-2026

   DESCRIPTION:
   - Thin adapter over the shared ExtDoorCommon DXF exporter factory, the same
     factory the Exterior Double Door uses.

   DEPENDENCIES:
   - @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__UiSystem__DxfExporter__.js
   - window.Na__ExtSingleDoor__LeafConfigResolver.na_resolve

   ============================================================================= */


// =============================================================================
// REGION | ExtSingleDoor DXF Exporter Module
// =============================================================================

const Na__ExtSingleDoor__DxfExporter = window.Na__ExtDoorCommon__DxfExporter.na_create({
    prefix                  : 'single_door',
    productLabel            : 'Exterior Single Door',
    na_resolver             : function () { return window.Na__ExtSingleDoor__LeafConfigResolver; },
    // One leaf, so the only leaf carries the exported handle circle.
    na_draw_handle_for_leaf : function () { return true; }
});


// =============================================================================
// REGION | Browser Global Attachment
// =============================================================================

window.Na__ExtSingleDoor__DxfExporter = Object.freeze(Na__ExtSingleDoor__DxfExporter);

// endregion -------------------------------------------------------------------


/* =============================================================================
   END OF FILE
   ============================================================================= */
