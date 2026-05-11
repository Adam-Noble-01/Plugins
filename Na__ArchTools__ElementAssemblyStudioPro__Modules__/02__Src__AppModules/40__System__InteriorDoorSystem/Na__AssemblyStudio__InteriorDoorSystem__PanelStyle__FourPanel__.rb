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
        # The horizontal cross-rail is centred at the door handle
        # height (handle_height_z_mm), clamped to fit inside the
        # inner perimeter. If no handle height is supplied it falls
        # back to the geometric mid-height of the inner perimeter.
        # The cross-rail thickness is driven by cross_rail_thickness_mm
        # (default 200 mm), independent of the shared inner_rail_t
        # thickness which governs the vertical mullion and joints.
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from Na__PanelDesignFrame.na_compute_layout
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @param cross_rail_thickness_mm [Numeric] Cross-rail height/thickness (mm)
        # @param handle_height_z_mm [Numeric, nil] Handle height above floor (mm)
        # @return [Integer] Number of edges drawn
        def self.na_build_face_lines(face_entities, layout, y_mm, cross_rail_thickness_mm = 200.0, handle_height_z_mm = nil)
            return 0 unless layout[:inner_perimeter_valid?]

            cross_t             = cross_rail_thickness_mm.to_f
            half_cross          = cross_t / 2.0
            half_mullion        = layout[:inner_rail_t] / 2.0

            cross_rail_z_centre = na_resolve_cross_rail_z_centre(layout, handle_height_z_mm, half_cross)
            mullion_x_centre    = (layout[:inner_x_min] + layout[:inner_x_max]) / 2.0

            cross_rails = [
                { :z_low => cross_rail_z_centre - half_cross, :z_high => cross_rail_z_centre + half_cross, :z_centre => cross_rail_z_centre }
            ]
            mullions = [
                { :x_left => mullion_x_centre - half_mullion, :x_right => mullion_x_centre + half_mullion, :x_centre => mullion_x_centre }
            ]

            count  = 0
            count += PanelDesignFrame.na_draw_inner_perimeter(face_entities, layout, y_mm, mullions, cross_rails)
            count += PanelDesignFrame.na_draw_horizontal_rail_pair(face_entities, layout, cross_rail_z_centre, mullions, y_mm, cross_t)
            count += PanelDesignFrame.na_draw_vertical_mullion_pair(face_entities, layout, mullion_x_centre, cross_rails, y_mm)

            DebugTools.na_debug_geometry("PanelDesign[FourPanel]: drew #{count} edges (cross-rail Z=#{cross_rail_z_centre.round(1)}mm, thickness=#{cross_t}mm)")
            count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Cross-Rail Positioning
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Cross-Rail Centre-Line Z Position
        # ------------------------------------------------------------
        # Prefers the door handle height so the mid-rail aligns with
        # the handle. The value is clamped so the cross-rail fully
        # sits within the inner perimeter. Falls back to geometric
        # mid-height when handle height is absent or out of range.
        #
        # @param layout [Hash] Layout from Na__PanelDesignFrame.na_compute_layout
        # @param handle_height_z_mm [Numeric, nil] Handle height above floor (mm)
        # @param half_cross [Numeric] Half the cross-rail thickness (mm)
        # @return [Numeric] Clamped cross-rail centre-line Z (mm)
        def self.na_resolve_cross_rail_z_centre(layout, handle_height_z_mm, half_cross)
            mid_z      = (layout[:inner_z_min] + layout[:inner_z_max]) / 2.0
            z_min_safe = layout[:inner_z_min] + half_cross                     # <-- Lowest safe centre
            z_max_safe = layout[:inner_z_max] - half_cross                     # <-- Highest safe centre

            return mid_z if z_min_safe >= z_max_safe                           # <-- Perimeter too small to subdivide

            candidate  = handle_height_z_mm.to_f
            return mid_z if candidate <= 0                                     # <-- No handle height supplied

            candidate.clamp(z_min_safe, z_max_safe)
        end
        private_class_method :na_resolve_cross_rail_z_centre
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelDesignStyles__FourPanel
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
