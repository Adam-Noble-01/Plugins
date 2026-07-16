# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - EXTERIOR DOOR COMMON - HANDLE BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__ExtDoorCommon__HandleBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__ExteriorDoorCommon
# MODULE     : Na__HandleBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Adapter that places an interior + exterior handle pair on a
#              single leaf by delegating to the Interior Door System's shared
#              3D handle builder. Used by every exterior door system.
#
# DESCRIPTION:
# - Extracted from the Exterior Double Door System handle adapter. The active-
#   leaf-only decision now lives in the calling composer; this module always
#   builds a handle pair for whatever leaf it is given (interior + exterior
#   instances, parented to the MOD group so they rotate with the leaf).
# - The exterior handle asset (e.g. Na__ExteriorDoor__Handle__Scroll) is
#   resolved by the Interior AssetLibrary which now falls back to the shared
#   ExteriorDoor__Handles__ bucket for unknown keys.
#
# INPUT handle_config (symbol keys):
#   :asset_key        Handle asset key stem
#   :height_mm        Handle height AFF
#   :backset_mm       Distance from the latch / meeting stile toward the hinge (mm)
#   :swing_direction  'Inward' | 'Outward'
#
# INPUT leaf: :is_active (informational), :dimensions {:width_mm,
#             :frame_depth_mm, :frame_wall_inset_mm}, :thickness_mm,
#             :side, :side_name, :index, :origin_x_mm, :hinge_x_mm, :width_mm
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative '../40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__'
require_relative '../40__System__InteriorDoorSystem/Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__'
require_relative 'Na__AssemblyStudio__ExtDoorCommon__GeometryHelpers__'

module Na__AssemblyStudio
module Na__ExteriorDoorCommon
module Na__HandleBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

    InteriorHandleBuilder = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__HandleBuilder3D
    AssetLibrary          = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary
    GeometryHelpers       = Na__AssemblyStudio::Na__ExteriorDoorCommon::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

    # FUNCTION | Build an Interior + Exterior Handle Pair on One Leaf
    # ------------------------------------------------------------
    # @param handle_config [Hash] Symbol-keyed handle placement config
    # @param entities      [Sketchup::Entities] Target entities (typically MOD)
    # @param leaf          [Hash] Leaf descriptor from the calling composer
    # @param material      [Sketchup::Material, nil] Optional handle material
    # @return [Hash] { :interior => ComponentInstance, :exterior => ComponentInstance }
    def self.na_build_leaf_handle(handle_config, entities, leaf, material = nil)
        # Re-read placement metadata (ScaleX / correction) from disk each build
        AssetLibrary.na_invalidate_handle_asset(handle_config[:asset_key]) if AssetLibrary.respond_to?(:na_invalidate_handle_asset)
        adapter_config = na_adapter_config(handle_config, leaf)
        adapter_leaf = na_adapter_leaf(handle_config, leaf)
        InteriorHandleBuilder.na_build_handles(adapter_config, entities, material, adapter_leaf)
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Adapter Mapping
# -----------------------------------------------------------------------------

    # HELPER FUNCTION | Map Exterior Handle Config to Interior Builder Keys
    # ------------------------------------------------------------
    def self.na_adapter_config(handle_config, leaf)
        dimensions = leaf[:dimensions]
        inset_mm = na_meeting_stile_inset_mm(handle_config, leaf)
        {
            'Na__DoorConfig__HandleAssetKey' => handle_config[:asset_key],
            'Na__DoorConfig__HandleHeight_mm' => GeometryHelpers.na_number(handle_config, :height_mm, 900),
            'Na__DoorConfig__HandleInsetFromLatch_mm' => inset_mm,
            'Na__DoorConfig__HandleAbsoluteX_mm' => na_handle_x_from_meeting_stile(leaf, inset_mm),
            'Na__DoorConfig__OpeningWidth_mm' => dimensions[:width_mm],
            'Na__DoorConfig__LiningThickness_mm' => 0,
            'Na__DoorConfig__PanelThickness_mm' => leaf[:thickness_mm],
            'Na__DoorConfig__WallDepth_mm' => dimensions[:frame_depth_mm],
            'Na__DoorConfig__LiningFaceOffset_mm' => dimensions[:frame_wall_inset_mm],
            'Na__DoorConfig__SwingDirection' => handle_config[:swing_direction] || 'Inward',
            'Na__DoorConfig__SwingSide' => leaf[:side_name]
        }
    end
    private_class_method :na_adapter_config
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Map Exterior Leaf Descriptor to Interior Leaf Shape
    # ------------------------------------------------------------
    # leaf_w_mm is reduced by the meeting-stile inset so the legacy
    # hinge±leaf_w formula (OffsetX=0) still insets correctly if an older
    # HandleBuilder3D without HandleAbsoluteX is loaded. Prefer AbsoluteX.
    def self.na_adapter_leaf(handle_config, leaf)
        inset_mm = na_meeting_stile_inset_mm(handle_config, leaf)
        {
            :index => leaf[:index],
            :swing_side => leaf[:side].to_s,
            :origin_x_mm => leaf[:origin_x_mm],
            :hinge_x_mm => leaf[:hinge_x_mm],
            :leaf_w_mm => [leaf[:width_mm].to_f - inset_mm, 1.0].max
        }
    end
    private_class_method :na_adapter_leaf
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Clamp Handle Inset from Meeting / Latch Stile
    # ------------------------------------------------------------
    def self.na_meeting_stile_inset_mm(handle_config, leaf)
        GeometryHelpers.na_clamp(
            GeometryHelpers.na_number(handle_config, :backset_mm, 40),
            20,
            [leaf[:width_mm].to_f / 2.0, 20].max
        )
    end
    private_class_method :na_meeting_stile_inset_mm
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Absolute Handle X from Meeting Stile Edge
    # ------------------------------------------------------------
    # Left leaf meeting edge is at the right of the leaf; right leaf meeting
    # edge is at the left. Inset always moves the spindle toward the hinge.
    def self.na_handle_x_from_meeting_stile(leaf, inset_mm)
        latch_x = leaf[:latch_x_mm]
        if latch_x.nil?
            left = leaf[:side].to_s.downcase == 'left'
            latch_x = left ? (leaf[:origin_x_mm].to_f + leaf[:width_mm].to_f) : leaf[:origin_x_mm].to_f
        end
        left = leaf[:side].to_s.downcase == 'left'
        left ? (latch_x.to_f - inset_mm.to_f) : (latch_x.to_f + inset_mm.to_f)
    end
    private_class_method :na_handle_x_from_meeting_stile
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__HandleBuilder
end # module Na__ExteriorDoorCommon
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
