# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - PANEL DESIGN: VERTICAL NARROW
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__PanelStyle__VerticalNarrow__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__PanelDesignStyles__VerticalNarrow
# AUTHOR     : Noble Architecture
# PURPOSE    : Subdivides the inner perimeter of a door panel face into a
#              series of equal-width vertical panes. The number of panes is
#              normalised against the user's preferred pane width slider so
#              the divisions stay visually consistent across panel widths.
# CREATED    : 03-May-2026
#
# DESCRIPTION:
# - Reads the inner-perimeter rect from the layout hash supplied by
#   Na__PanelDesignFrame.
# - Computes N = max(1, (inner_w / preferred_pane_w_mm).round) so the actual
#   pane width hugs the slider value as the door width changes.
# - Draws (N-1) single vertical edges spanning the inner perimeter top-to-bottom.
# - Returns the count of edges drawn for diagnostics.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelDesignFrame__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__PanelDesignStyles__VerticalNarrow

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools       = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers  = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers
        PanelDesignFrame = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignFrame

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Vertical-Narrow Subdivision Lines
        # ------------------------------------------------------------
        # Draws the inner perimeter rectangle (no clipping, since the
        # vertical dividers below are zero-thickness centerlines so
        # there is no thickness band to clip against), then adds one
        # full-height divider per internal pane.
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from Na__PanelDesignFrame.na_compute_layout
        # @param preferred_pane_w_mm [Numeric] Slider-driven preferred pane width
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @return [Integer] Number of edges drawn
        def self.na_build_face_lines(face_entities, layout, preferred_pane_w_mm, y_mm)
            return 0 unless layout[:inner_perimeter_valid?]

            count = PanelDesignFrame.na_draw_inner_perimeter(face_entities, layout, y_mm)

            divisions     = na_compute_division_count(layout[:inner_w], preferred_pane_w_mm)
            return count if divisions <= 1                                      # <-- 1 pane = no internal dividers

            inner_x_min   = layout[:inner_x_min]
            inner_x_max   = layout[:inner_x_max]
            inner_z_min   = layout[:inner_z_min]
            inner_z_max   = layout[:inner_z_max]
            pane_width    = (inner_x_max - inner_x_min) / divisions.to_f

            (1...divisions).each do |i|
                x_div = inner_x_min + (pane_width * i)
                count += 1 if GeometryHelpers.na_create_xz_line(
                    face_entities, x_div, inner_z_min, x_div, inner_z_max, y_mm
                )
            end

            DebugTools.na_debug_geometry(
                "PanelDesign[VerticalNarrow]: #{divisions} panes, #{count} edges (pane_w=#{pane_width.round(1)}mm)"
            )
            count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Compute Division Count Normalised Against Preferred Width
        # ------------------------------------------------------------
        # Returns the integer number of equal-width panes that fits
        # the inner perimeter most closely to the slider value.
        # Always >= 1 (never produces zero panes).
        def self.na_compute_division_count(inner_w_mm, preferred_pane_w_mm)
            return 1 if inner_w_mm <= 0
            return 1 if preferred_pane_w_mm.to_f <= 0

            divisions = (inner_w_mm.to_f / preferred_pane_w_mm.to_f).round
            divisions = 1 if divisions < 1
            divisions
        end
        private_class_method :na_compute_division_count
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelDesignStyles__VerticalNarrow
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
