# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - HANDLE BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__HandleBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__HandleBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Places the chosen handle asset on every door and drawer front of
#              a Flat or Shaker unit, at the anchors the layout resolved.
# CREATED    : 29-Oct-2026
#
# DESCRIPTION:
# - Cabinet handle assets stand up from the door: origin at the centre of the
#   fixings on the door face, X along the bar, Z out of the door (the door
#   handle assets lie on their back; this family does not need turning).
# - A vertical bar maps X to the unit's Z; a horizontal bar maps X to the
#   unit's X. Asset Z always maps to the unit's -Y, out of the front face.
# - The layout anchors a bar by one end or its centre; the asset's own
#   Na__CabinetPlacement__Length_mm turns an end anchor into the centre.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative 'Na__AssemblyStudio__Cabinetry__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__Cabinetry__AssetLibrary__'
require_relative 'Na__AssemblyStudio__Cabinetry__AssetMeshBuilder__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__HandleBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        GeometryHelpers   = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__GeometryHelpers
        AssetLibrary      = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__AssetLibrary
        AssetMeshBuilder  = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__AssetMeshBuilder

        NA_GROUP_NAME = "Na__Cabinet__Handles".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Place Every Handle (Nil When There Are None)
        # ------------------------------------------------------------
        # @return [Sketchup::Group, nil]
        def self.na_build(layout, entities, handle_key, materials)
            return nil if layout[:handles].empty?
            definition = AssetMeshBuilder.na_handle_definition(handle_key)
            unless definition
                DebugTools.na_debug_warn("Handle asset '#{handle_key}' could not be built - handles skipped")
                return nil
            end
            asset  = AssetLibrary.na_load(:handles, handle_key)
            length = AssetLibrary.na_metadata_value(asset, "Na__CabinetPlacement__Length_mm", 0).to_f

            group = GeometryHelpers.na_add_group(entities, NA_GROUP_NAME)
            layout[:handles].each do |handle|
                instance = group.entities.add_instance(definition, na_handle_transform(handle, length))
                instance.name     = "Na__Handle__#{handle[:front]}"
                instance.material = materials[:handle] if materials[:handle]
            end
            na_paint_edges(group)
            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where a Handle's Fixing Centre Sits (Pure, mm)
        # ------------------------------------------------------------
        # @param handle [Hash] { :x, :z, :orientation, :anchor }
        # @param length [Float] the handle's overall length (mm)
        # @return [Array(Float, Float)] [x, z] of the fixing centre
        def self.na_centre_of(handle, length)
            half = length / 2.0
            case handle[:anchor]
            when "top"    then [handle[:x], handle[:z] - half]
            when "bottom" then [handle[:x], handle[:z] + half]
            when "right"  then [handle[:x] - half, handle[:z]]
            when "left"   then [handle[:x] + half, handle[:z]]
            else               [handle[:x], handle[:z]]
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Instance Transform for One Handle
        # ------------------------------------------------------------
        # Columns: asset X, asset Y, asset Z in unit axes. Both sets are
        # right-handed (X x Y = Z), so the handle is never mirrored.
        def self.na_handle_transform(handle, length)
            cx, cz = na_centre_of(handle, length)
            origin = GeometryHelpers.na_point(cx, handle[:y], cz)
            if handle[:orientation] == "vertical"
                Geom::Transformation.axes(origin, Geom::Vector3d.new(0, 0, 1), Geom::Vector3d.new(-1, 0, 0), Geom::Vector3d.new(0, -1, 0))
            else
                Geom::Transformation.axes(origin, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1), Geom::Vector3d.new(0, -1, 0))
            end
        end
        private_class_method :na_handle_transform
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Standard Dark Grey Edges, as on the Door Handles
        # ------------------------------------------------------------
        def self.na_paint_edges(group)
            EdgeColourManager.na_apply_edge_colour_to_group(group, EdgeColourManager::NA_DEFAULT_DARK_GREY_KEY)
        rescue StandardError => e
            DebugTools.na_debug_warn("Handle edge colour skipped: #{e.message}")
        end
        private_class_method :na_paint_edges
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__HandleBuilder
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
