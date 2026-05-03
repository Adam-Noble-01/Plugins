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
# - Adds two horizontal cross-rail centerlines at z = inner_z_min + (1/3)*inner_h
#   and z = inner_z_min + (2/3)*inner_h. Each is a SINGLE edge (no rail-pair
#   thickness) so the elevation reads as a clean architectural division.
# - No vertical mullion - each tier is a single full-width panel.
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
    module Na__PanelDesignStyles__HorizontalThree

# -----------------------------------------------------------------------------
# REGION | Module References & Constants
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers

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
        # The shared frame has already drawn the inner perimeter
        # rectangle. This function adds two horizontal cross-rails
        # at the one-third and two-thirds Z boundaries of the inner
        # perimeter. No vertical mullion is added.
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
            inner_h       = layout[:inner_h]

            lower_z_centre = inner_z_min + (inner_h * NA_LOWER_BOUNDARY_RATIO)
            upper_z_centre = inner_z_min + (inner_h * NA_UPPER_BOUNDARY_RATIO)

            count  = 0
            count += 1 if GeometryHelpers.na_create_xz_line(
                face_entities, inner_x_min, lower_z_centre, inner_x_max, lower_z_centre, y_mm
            )
            count += 1 if GeometryHelpers.na_create_xz_line(
                face_entities, inner_x_min, upper_z_centre, inner_x_max, upper_z_centre, y_mm
            )

            DebugTools.na_debug_geometry(
                "PanelDesign[HorizontalThree]: drew #{count} division edges"
            )
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
