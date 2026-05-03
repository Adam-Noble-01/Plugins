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
# - Adds one horizontal cross-rail centerline at the centre of the
#   inner perimeter Z range and one vertical mullion centerline at
#   the centre of the inner perimeter X range. Each is a SINGLE edge
#   (no rail-pair thickness) so the elevation reads as a clean 2x2
#   architectural division.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__PanelDesignStyles__FourPanel

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Four-Panel 2x2 Grid Subdivision Lines
        # ------------------------------------------------------------
        # The shared frame has already drawn the inner perimeter
        # rectangle. This function adds one horizontal cross-rail
        # and one vertical mullion at the inner-perimeter centre.
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from Na__PanelDesignFrame.na_compute_layout
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @return [Integer] Number of edges drawn
        def self.na_build_face_lines(face_entities, layout, y_mm)
            return 0 unless layout[:inner_perimeter_valid?]

            inner_x_min   = layout[:inner_x_min]
            inner_x_max   = layout[:inner_x_max]
            inner_z_min   = layout[:inner_z_min]
            inner_z_max   = layout[:inner_z_max]

            cross_rail_z_centre = (inner_z_min + inner_z_max) / 2.0
            mullion_x_centre    = (inner_x_min + inner_x_max) / 2.0

            count  = 0
            count += 1 if GeometryHelpers.na_create_xz_line(
                face_entities, inner_x_min, cross_rail_z_centre, inner_x_max, cross_rail_z_centre, y_mm
            )
            count += 1 if GeometryHelpers.na_create_xz_line(
                face_entities, mullion_x_centre, inner_z_min, mullion_x_centre, inner_z_max, y_mm
            )

            DebugTools.na_debug_geometry(
                "PanelDesign[FourPanel]: drew #{count} division edges"
            )
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
