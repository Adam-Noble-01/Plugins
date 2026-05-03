# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - PANEL DESIGN FRAME
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__PanelDesignFrame__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__PanelDesignFrame
# AUTHOR     : Noble Architecture
# PURPOSE    : Shared geometry helper for the door panel design subsystem.
#              Resolves the four perimeter constraints (top rail, bottom rail,
#              left stile, right stile) into a single layout hash that all
#              style builders consume, and draws the inner-perimeter rectangle
#              that every style shares.
# CREATED    : 03-May-2026
#
# DESCRIPTION:
# - Encapsulates the maths for computing where the inner perimeter sits on a
#   given panel face. Style-specific subdividers (VerticalNarrow, FourPanel,
#   ClassicalSixPanel, HorizontalThree) take this layout and add only their
#   own internal rails/mullions on top.
# - All inputs and outputs are millimetres; conversion to inches happens
#   inside the GeometryHelpers primitives, never here.
#
# COORDINATE SYSTEM (MOD-local):
# - X+ runs left -> right across the door opening width.
# - Y+ runs front -> back through the wall depth.
# - Z+ runs upwards.
# - The panel face linework is authored in the XZ plane at constant Y.
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
    module Na__PanelDesignFrame

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # CONSTANTS | Minimum Inner Perimeter Dimensions
        # ------------------------------------------------------------
        # If the user dials the rails or stiles up too far the inner
        # perimeter would invert. The frame falls back to a single
        # outer rectangle (no subdivisions) when this happens; the
        # builder uses NA_MIN_INNER_DIMENSION_MM to guard subdivision.
        NA_MIN_INNER_DIMENSION_MM = 50.0
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Layout Computation
# -----------------------------------------------------------------------------

        # FUNCTION | Compute the Inner-Perimeter Layout in MOD-Local Coordinates
        # ------------------------------------------------------------
        # Builds a single layout hash carrying every value a style
        # builder needs: the outer panel rect, the inner perimeter
        # rect, the four slider values, and a derived flag indicating
        # whether subdivisions are even worth drawing.
        #
        # @param panel_origin_x_mm [Numeric] X coord of panel bottom-left
        # @param panel_origin_z_mm [Numeric] Z coord of panel bottom-left
        # @param panel_w_mm [Numeric] Panel width
        # @param panel_h_mm [Numeric] Panel height
        # @param stile_w_mm [Numeric] Side stile width (both sides)
        # @param top_rail_mm [Numeric] Top rail height
        # @param bottom_rail_mm [Numeric] Bottom rail height
        # @return [Hash] Layout hash (see keys below)
        def self.na_compute_layout(panel_origin_x_mm, panel_origin_z_mm,
                                   panel_w_mm, panel_h_mm,
                                   stile_w_mm, top_rail_mm, bottom_rail_mm)

            panel_x_min  = panel_origin_x_mm.to_f
            panel_x_max  = panel_x_min + panel_w_mm.to_f
            panel_z_min  = panel_origin_z_mm.to_f
            panel_z_max  = panel_z_min + panel_h_mm.to_f

            inner_x_min  = panel_x_min + stile_w_mm.to_f
            inner_x_max  = panel_x_max - stile_w_mm.to_f
            inner_z_min  = panel_z_min + bottom_rail_mm.to_f
            inner_z_max  = panel_z_max - top_rail_mm.to_f

            inner_w      = inner_x_max - inner_x_min
            inner_h      = inner_z_max - inner_z_min

            {
                :panel_x_min      => panel_x_min,
                :panel_x_max      => panel_x_max,
                :panel_z_min      => panel_z_min,
                :panel_z_max      => panel_z_max,
                :inner_x_min      => inner_x_min,
                :inner_x_max      => inner_x_max,
                :inner_z_min      => inner_z_min,
                :inner_z_max      => inner_z_max,
                :inner_w          => inner_w,
                :inner_h          => inner_h,
                :stile_w          => stile_w_mm.to_f,
                :top_rail         => top_rail_mm.to_f,
                :bottom_rail      => bottom_rail_mm.to_f,
                :inner_perimeter_valid? => (inner_w >= NA_MIN_INNER_DIMENSION_MM &&
                                            inner_h >= NA_MIN_INNER_DIMENSION_MM)
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Frame Drawing
# -----------------------------------------------------------------------------

        # FUNCTION | Draw the Inner-Perimeter Rectangle
        # ------------------------------------------------------------
        # The four edges of the inner perimeter are the visible
        # boundary between the perimeter rails / stiles and the
        # subdivided inner panels. Every style draws this rectangle
        # exactly once before adding its own internal divisions.
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from na_compute_layout
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @return [Integer] Number of edges added (4 on success)
        def self.na_draw_inner_perimeter(face_entities, layout, y_mm)
            return 0 unless layout[:inner_perimeter_valid?]

            x_min = layout[:inner_x_min]
            x_max = layout[:inner_x_max]
            z_min = layout[:inner_z_min]
            z_max = layout[:inner_z_max]

            count  = 0
            count += 1 if GeometryHelpers.na_create_xz_line(face_entities, x_min, z_min, x_max, z_min, y_mm)
            count += 1 if GeometryHelpers.na_create_xz_line(face_entities, x_max, z_min, x_max, z_max, y_mm)
            count += 1 if GeometryHelpers.na_create_xz_line(face_entities, x_max, z_max, x_min, z_max, y_mm)
            count += 1 if GeometryHelpers.na_create_xz_line(face_entities, x_min, z_max, x_min, z_min, y_mm)

            DebugTools.na_debug_geometry("PanelDesignFrame: drew inner perimeter (#{count} edges) at Y=#{y_mm}mm")
            count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelDesignFrame
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
