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
# - Builds two horizontal cross-rails AS PAIRS (each a pair of parallel
#   edges spaced by inner_rail_t) at the tier boundaries, plus one
#   full-height vertical mullion AS A PAIR at the inner-perimeter centre.
# - All edges are clipped at every perpendicular rail's thickness band
#   so each joint reads as a clean butt-joint - no segments visible
#   inside another rail's thickness.
# - The inner perimeter rectangle is drawn here (not by the builder)
#   because the perimeter's left/right edges must be clipped by both
#   cross-rails and the perimeter's top/bottom edges must be clipped
#   by the mullion.
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
    module Na__PanelDesignStyles__ClassicalSixPanel

# -----------------------------------------------------------------------------
# REGION | Module References & Constants
# -----------------------------------------------------------------------------

        DebugTools       = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        PanelDesignFrame = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignFrame

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
        # Computes the rail/mullion specs, then draws the inner
        # perimeter and the two cross-rail pairs and one mullion pair
        # using the shared frame helpers (which apply joint clipping).
        #
        # Each cross-rail uses its own thickness so the proportions
        # match a real Georgian door:
        #   - lock_rail_t_mm  : lower lockrail at ~38% height (default 200 mm)
        #   - mid_rail_t_mm   : upper mid-rail  at ~76% height (default 125 mm)
        # The vertical mullion keeps using layout[:inner_rail_t] (default 70 mm).
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from Na__PanelDesignFrame.na_compute_layout
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @param lock_rail_t_mm [Numeric] Lower lockrail thickness (mm)
        # @param mid_rail_t_mm [Numeric] Upper mid-rail thickness (mm)
        # @return [Integer] Number of edges drawn
        def self.na_build_face_lines(face_entities, layout, y_mm, lock_rail_t_mm = 200.0, mid_rail_t_mm = 125.0)
            return 0 unless layout[:inner_perimeter_valid?]

            half_mullion        = layout[:inner_rail_t] / 2.0
            half_lock           = lock_rail_t_mm.to_f / 2.0
            half_mid            = mid_rail_t_mm.to_f  / 2.0
            inner_h             = layout[:inner_h]
            inner_z_min         = layout[:inner_z_min]
            inner_x_min         = layout[:inner_x_min]
            inner_x_max         = layout[:inner_x_max]

            cross_low_z_centre  = inner_z_min + (inner_h * NA_TIER_RATIO_BOTTOM)
            cross_high_z_centre = inner_z_min + (inner_h * (NA_TIER_RATIO_BOTTOM + NA_TIER_RATIO_MIDDLE))
            mullion_x_centre    = (inner_x_min + inner_x_max) / 2.0

            cross_rails = [
                { :z_low => cross_low_z_centre  - half_lock, :z_high => cross_low_z_centre  + half_lock, :z_centre => cross_low_z_centre  },
                { :z_low => cross_high_z_centre - half_mid,  :z_high => cross_high_z_centre + half_mid,  :z_centre => cross_high_z_centre  }
            ]
            mullions = [
                { :x_left => mullion_x_centre - half_mullion, :x_right => mullion_x_centre + half_mullion, :x_centre => mullion_x_centre }
            ]

            count  = 0
            count += PanelDesignFrame.na_draw_inner_perimeter(face_entities, layout, y_mm, mullions, cross_rails)
            count += PanelDesignFrame.na_draw_horizontal_rail_pair(face_entities, layout, cross_low_z_centre,  mullions, y_mm, lock_rail_t_mm)
            count += PanelDesignFrame.na_draw_horizontal_rail_pair(face_entities, layout, cross_high_z_centre, mullions, y_mm, mid_rail_t_mm)
            mullions.each do |m|
                count += PanelDesignFrame.na_draw_vertical_mullion_pair(face_entities, layout, m[:x_centre], cross_rails, y_mm)
            end

            DebugTools.na_debug_geometry("PanelDesign[ClassicalSixPanel]: drew #{count} edges (lock=#{lock_rail_t_mm}mm, mid=#{mid_rail_t_mm}mm)")
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
