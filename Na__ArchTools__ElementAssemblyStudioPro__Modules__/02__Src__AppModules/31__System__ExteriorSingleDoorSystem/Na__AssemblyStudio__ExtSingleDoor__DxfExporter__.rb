# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR - DXF EXPORTER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__DxfExporter__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# MODULE     : Na__DxfExporter
# AUTHOR     : Noble Architecture
# PURPOSE    : Emit the exterior single door as DXF (elevation + plan) for the
#              Export DXF button. Thin adapter over the shared ExtDoorCommon
#              exporter - the same one the double door uses - so a single door
#              exports its stiles, rails, fielded panels, glazing bars, handle
#              and swing arc instead of falling through to the window exporter.
#
# @delegate: ../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__DxfExporter__.rb
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__ExtSingleDoor__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__ExtSingleDoor__LeafLayoutResolver__'
require_relative 'Na__AssemblyStudio__ExtSingleDoor__PanelLayoutResolver__'
require_relative '../30__System__ExteriorDoorCommon__/Na__AssemblyStudio__ExtDoorCommon__DxfExporter__'

module Na__AssemblyStudio
module Na__ExteriorSingleDoorSystem
module Na__DxfExporter

# -----------------------------------------------------------------------------
# REGION | Product Descriptor
# -----------------------------------------------------------------------------

    SharedExporter = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__DxfExporter

    NA_PRODUCT = {
        :prefix         => 'single_door',
        :label          => 'Exterior Single Door',
        :leaf_resolver  => Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__LeafLayoutResolver,
        :panel_resolver => Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__PanelLayoutResolver,
        :leaf_count     => 1,
        # One leaf, so the only leaf carries the exported handle.
        :handle_leaf    => ->(_config, _leaf) { true }
    }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build DXF Entity Descriptors for a Single-Door Config
    # ------------------------------------------------------------
    def self.na_build_entities(config)
        SharedExporter.na_build_entities(NA_PRODUCT, config)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Export a Single-Door Config as ASCII DXF or Into a Writer
    # ------------------------------------------------------------
    def self.na_export(config, writer = nil)
        SharedExporter.na_export(NA_PRODUCT, config, writer)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Export Alias Used by the Dialog Callback
    # ------------------------------------------------------------
    def self.na_export_dxf(config, writer = nil)
        na_export(config, writer)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__DxfExporter
end # module Na__ExteriorSingleDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
