# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - PANEL DESIGN: CLASSICAL SIX-PANEL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__ClassicalSix__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__PanelDesignStyles__ClassicalSixPanel
# AUTHOR     : Noble Architecture
# PURPOSE    : Subdivides the inner perimeter of a door panel face into the
#              traditional Georgian six-panel layout: three horizontal tiers
#              (top tier shorter, middle and bottom equal height) split down
#              the middle by a single vertical mullion -> 2 + 2 + 2 panels.
# CREATED    : 03-May-2026
#
# DESCRIPTION:
# - Reads the inner-perimeter rect from the layout hash supplied by
#   Na__PanelDesignFrame.
# - Splits the inner height into three tiers using NA_TIER_RATIOS
#   (24% top / 38% middle / 38% bottom). The top tier is intentionally
#   shorter to match the classical Georgian proportion.
# - Adds two horizontal cross-rail centerlines at the tier boundaries
#   and one full-height vertical mullion centerline at the inner-perimeter
#   centre. Each rail / mullion is a SINGLE edge (no rail-pair thickness)
#   so the elevation reads as a clean architectural division.
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
    module Na__PanelDesignStyles__ClassicalSixPanel

# -----------------------------------------------------------------------------
# REGION | Module References & Constants
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers

        # CONSTANTS | Tier Height Ratios (must sum to 1.0)
        # ------------------------------------------------------------
        # Bottom -> Middle -> Top, matching Georgian convention where
        # the top tier reads as visually lighter (shorter) than the
        # middle and bottom tiers.
        NA_TIER_RATIO_BOTTOM = 0.38
        NA_TIER_RATIO_MIDDLE = 0.38
        NA_TIER_RATIO_TOP    = 0.24
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Classical Six-Panel Subdivision Lines
        # ------------------------------------------------------------
        # The shared frame has already drawn the inner perimeter
        # rectangle. This function adds the two horizontal cross-rails
        # and the single vertical mullion that produce the 2+2+2 layout.
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
            inner_h       = layout[:inner_h]

            tier_boundary_lower = inner_z_min + (inner_h * NA_TIER_RATIO_BOTTOM)
            tier_boundary_upper = inner_z_min + (inner_h * (NA_TIER_RATIO_BOTTOM + NA_TIER_RATIO_MIDDLE))
            mullion_x_centre    = (inner_x_min + inner_x_max) / 2.0

            count  = 0
            count += 1 if GeometryHelpers.na_create_xz_line(
                face_entities, inner_x_min, tier_boundary_lower, inner_x_max, tier_boundary_lower, y_mm
            )
            count += 1 if GeometryHelpers.na_create_xz_line(
                face_entities, inner_x_min, tier_boundary_upper, inner_x_max, tier_boundary_upper, y_mm
            )
            count += 1 if GeometryHelpers.na_create_xz_line(
                face_entities, mullion_x_centre, inner_z_min, mullion_x_centre, inner_z_max, y_mm
            )

            DebugTools.na_debug_geometry(
                "PanelDesign[ClassicalSixPanel]: drew #{count} division edges"
            )
            count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelDesignStyles__ClassicalSixPanel
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
