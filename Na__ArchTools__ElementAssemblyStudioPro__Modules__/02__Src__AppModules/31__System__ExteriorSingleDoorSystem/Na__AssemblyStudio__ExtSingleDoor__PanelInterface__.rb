# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR SINGLE DOOR SYSTEM PANEL INTERFACE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtSingleDoor__PanelInterface__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorSingleDoorSystem
# PURPOSE    : Inter-system contract used by WindowSystem to construct door
#              panels inside a casement frame and to fuse the resulting door
#              panel + trim groups during the FuseParts pipeline.
#
# CONTRACT
#   DoorPanelContext = Struct.new(
#     :entities, :panel_id,
#     :panel_x, :panel_z, :panel_width, :panel_height,
#     :casement_depth, :frame_wall_inset, :casement_inset,
#     :params, :frame_material
#   )
#
#   PanelInterface.na_build_panel(context)   -> Sketchup::Group | nil
#   PanelInterface.na_fuse_panel_steps(ents) -> { fused, failed, skipped }
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__ExtSingleDoor__GeometryBuilder__DoorPanel__'
require_relative 'Na__AssemblyStudio__ExtSingleDoor__FuseParts__DoorPanel__'

module Na__AssemblyStudio
    module Na__ExteriorSingleDoorSystem

        DoorPanelContext = Struct.new(
            :entities,
            :panel_id,
            :panel_x, :panel_z,
            :panel_width, :panel_height,
            :casement_depth, :frame_wall_inset, :casement_inset,
            :params, :frame_material
        )

        module PanelInterface

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

            def self.na_build_panel(context)
                builder = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__DoorPanelGeometryBuilder
                builder.na_create_door_panel_section(
                    context.entities,
                    context.panel_id,
                    context.panel_x,
                    context.panel_z,
                    context.panel_width,
                    context.panel_height,
                    context.params,
                    context.frame_material
                )
            rescue StandardError => e
                DebugTools.na_debug_error("PanelInterface.na_build_panel failed", e)
                nil
            end

            def self.na_fuse_panel_steps(entities)
                fuse = Na__AssemblyStudio::Na__ExteriorSingleDoorSystem::Na__FuseParts__DoorPanel
                fuse.na_fuse_door_panels(entities)
                    .merge!(fuse.na_fuse_door_trim(entities)) { |_k, a, b| a + b }
            rescue StandardError => e
                DebugTools.na_debug_error("PanelInterface.na_fuse_panel_steps failed", e)
                { :fused => 0, :failed => 1, :skipped => 0 }
            end

        end

    end
end
