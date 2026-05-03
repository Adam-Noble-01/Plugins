# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - PANEL DESIGN: HORIZONTAL THREE
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__HorizontalThree__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__PanelDesignStyles__HorizontalThree
# AUTHOR     : Noble Architecture
# PURPOSE    : Subdivides the inner perimeter of a door panel face into three
#              equal-height horizontal panels (no vertical mullion). Two
#              horizontal cross-rails divide the inner perimeter at one-third
#              and two-thirds of its height.
# CREATED    : 03-May-2026
#
# DESCRIPTION:
# - Reads the inner-perimeter rect from the layout hash supplied by
#   Na__PanelDesignFrame.
# - Builds two horizontal cross-rails AS PAIRS at z = (1/3)*inner_h
#   and z = (2/3)*inner_h, each spaced by inner_rail_t.
# - No vertical mullion - each tier is a single full-width panel.
# - The inner perimeter's left/right verticals are clipped at every
#   cross-rail's thickness band so the joints with the perimeter
#   read as clean butt-joints.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelDesignFrame__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__PanelDesignStyles__HorizontalThree

# -----------------------------------------------------------------------------
# REGION | Module References & Constants
# -----------------------------------------------------------------------------

        DebugTools       = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        PanelDesignFrame = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignFrame

        # CONSTANTS | Tier Boundary Ratios
        # ------------------------------------------------------------
        NA_LOWER_BOUNDARY_RATIO = 1.0 / 3.0
        NA_UPPER_BOUNDARY_RATIO = 2.0 / 3.0
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Horizontal-Three Subdivision Lines
        # ------------------------------------------------------------
        # Computes the cross-rail specs, then draws the inner perimeter
        # and two cross-rail pairs using the shared frame helpers
        # (which apply joint clipping where the rails meet the
        # perimeter's left/right verticals). No mullions in this style.
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from Na__PanelDesignFrame.na_compute_layout
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @return [Integer] Number of edges drawn
        def self.na_build_face_lines(face_entities, layout, y_mm)
            return 0 unless layout[:inner_perimeter_valid?]

            half_t          = layout[:inner_rail_t] / 2.0
            inner_z_min     = layout[:inner_z_min]
            inner_h         = layout[:inner_h]
            lower_z_centre  = inner_z_min + (inner_h * NA_LOWER_BOUNDARY_RATIO)
            upper_z_centre  = inner_z_min + (inner_h * NA_UPPER_BOUNDARY_RATIO)

            cross_rails = [
                { :z_low => lower_z_centre - half_t, :z_high => lower_z_centre + half_t, :z_centre => lower_z_centre },
                { :z_low => upper_z_centre - half_t, :z_high => upper_z_centre + half_t, :z_centre => upper_z_centre }
            ]
            mullions = []

            count  = 0
            count += PanelDesignFrame.na_draw_inner_perimeter(face_entities, layout, y_mm, mullions, cross_rails)
            cross_rails.each do |cr|
                count += PanelDesignFrame.na_draw_horizontal_rail_pair(face_entities, layout, cr[:z_centre], mullions, y_mm)
            end

            DebugTools.na_debug_geometry("PanelDesign[HorizontalThree]: drew #{count} edges")
            count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelDesignStyles__HorizontalThree
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
