# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - PANEL DESIGN: FOUR PANEL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__FourPanel__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__PanelDesignStyles__FourPanel
# AUTHOR     : Noble Architecture
# PURPOSE    : Subdivides the inner perimeter of a door panel face into a
#              classic four-panel 2x2 grid: one horizontal cross-rail at
#              the inner-perimeter mid-height + one full-height vertical
#              mullion at the inner-perimeter mid-width.
# CREATED    : 03-May-2026
#
# DESCRIPTION:
# - Reads the inner-perimeter rect from the layout hash supplied by
#   Na__PanelDesignFrame.
# - Builds one horizontal cross-rail AS A PAIR at the centre of the
#   inner perimeter Z range, and one vertical mullion AS A PAIR at
#   the centre of the inner perimeter X range. The rail thickness is
#   driven by Na__DoorConfig__PanelDesignInnerRailThickness_mm.
# - All edges (perimeter, cross-rail pair, mullion pair) are clipped
#   at every perpendicular rail's thickness band so each joint reads
#   as a clean butt-joint.
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
    module Na__PanelDesignStyles__FourPanel

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools       = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        PanelDesignFrame = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignFrame

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Four-Panel 2x2 Grid Subdivision Lines
        # ------------------------------------------------------------
        # Computes the rail/mullion specs, then draws the inner
        # perimeter, one cross-rail pair and one mullion pair using
        # the shared frame helpers (which apply joint clipping).
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from Na__PanelDesignFrame.na_compute_layout
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @return [Integer] Number of edges drawn
        def self.na_build_face_lines(face_entities, layout, y_mm)
            return 0 unless layout[:inner_perimeter_valid?]

            half_t              = layout[:inner_rail_t] / 2.0
            cross_rail_z_centre = (layout[:inner_z_min] + layout[:inner_z_max]) / 2.0
            mullion_x_centre    = (layout[:inner_x_min] + layout[:inner_x_max]) / 2.0

            cross_rails = [
                { :z_low => cross_rail_z_centre - half_t, :z_high => cross_rail_z_centre + half_t, :z_centre => cross_rail_z_centre }
            ]
            mullions = [
                { :x_left => mullion_x_centre - half_t, :x_right => mullion_x_centre + half_t, :x_centre => mullion_x_centre }
            ]

            count  = 0
            count += PanelDesignFrame.na_draw_inner_perimeter(face_entities, layout, y_mm, mullions, cross_rails)
            count += PanelDesignFrame.na_draw_horizontal_rail_pair(face_entities, layout, cross_rail_z_centre, mullions, y_mm)
            count += PanelDesignFrame.na_draw_vertical_mullion_pair(face_entities, layout, mullion_x_centre, cross_rails, y_mm)

            DebugTools.na_debug_geometry("PanelDesign[FourPanel]: drew #{count} edges")
            count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelDesignStyles__FourPanel
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
