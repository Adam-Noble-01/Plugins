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
        # @param inner_rail_t_mm [Numeric] Inner cross-rail / mullion thickness
        # @return [Hash] Layout hash (see keys below)
        def self.na_compute_layout(panel_origin_x_mm, panel_origin_z_mm,
                                   panel_w_mm, panel_h_mm,
                                   stile_w_mm, top_rail_mm, bottom_rail_mm,
                                   inner_rail_t_mm)

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
                :inner_rail_t     => inner_rail_t_mm.to_f,
                :inner_perimeter_valid? => (inner_w >= NA_MIN_INNER_DIMENSION_MM &&
                                            inner_h >= NA_MIN_INNER_DIMENSION_MM)
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Frame Drawing
# -----------------------------------------------------------------------------

        # FUNCTION | Draw the Inner-Perimeter Rectangle With Joint Clipping
        # ------------------------------------------------------------
        # The four edges of the inner perimeter are the visible
        # boundary between the perimeter rails/stiles and the
        # subdivided inner panels. Each edge is broken at every
        # perpendicular internal rail/mullion that meets it so the
        # joints read as clean butt-joints (no short segment of the
        # perimeter visible inside any rail's thickness band).
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from na_compute_layout
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @param mullions [Array<Hash>] Each entry: { :x_left, :x_right }
        #   - sorted ascending by :x_left, non-overlapping
        # @param cross_rails [Array<Hash>] Each entry: { :z_low, :z_high }
        #   - sorted ascending by :z_low, non-overlapping
        # @return [Integer] Number of edges added
        def self.na_draw_inner_perimeter(face_entities, layout, y_mm, mullions = [], cross_rails = [])
            return 0 unless layout[:inner_perimeter_valid?]

            x_min   = layout[:inner_x_min]
            x_max   = layout[:inner_x_max]
            z_min   = layout[:inner_z_min]
            z_max   = layout[:inner_z_max]
            x_gaps  = na_mullions_to_x_gaps(mullions)
            z_gaps  = na_cross_rails_to_z_gaps(cross_rails)

            count  = 0
            count += GeometryHelpers.na_create_horizontal_segmented(face_entities, x_min, x_max, z_min, y_mm, x_gaps)
            count += GeometryHelpers.na_create_horizontal_segmented(face_entities, x_min, x_max, z_max, y_mm, x_gaps)
            count += GeometryHelpers.na_create_vertical_segmented(face_entities, x_min, z_min, z_max, y_mm, z_gaps)
            count += GeometryHelpers.na_create_vertical_segmented(face_entities, x_max, z_min, z_max, y_mm, z_gaps)

            DebugTools.na_debug_geometry("PanelDesignFrame: drew inner perimeter (#{count} edges) at Y=#{y_mm}mm")
            count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Horizontal Cross-Rail as a Gap-Clipped Pair
        # ------------------------------------------------------------
        # A cross-rail is rendered as TWO parallel horizontal edges at
        # z = z_centre +/- (inner_rail_t / 2), spanning the inner
        # perimeter X range and clipped at every mullion's X band so
        # the joint with the mullion reads as a clean butt-joint.
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from na_compute_layout
        # @param z_centre_mm [Numeric] Centre-line Z of the cross-rail (mm)
        # @param mullions [Array<Hash>] Each entry: { :x_left, :x_right }
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @return [Integer] Number of edges added
        def self.na_draw_horizontal_rail_pair(face_entities, layout, z_centre_mm, mullions, y_mm)
            half_t = layout[:inner_rail_t] / 2.0
            x_min  = layout[:inner_x_min]
            x_max  = layout[:inner_x_max]
            x_gaps = na_mullions_to_x_gaps(mullions)
            z_top  = z_centre_mm + half_t
            z_bot  = z_centre_mm - half_t

            count  = 0
            count += GeometryHelpers.na_create_horizontal_segmented(face_entities, x_min, x_max, z_top, y_mm, x_gaps)
            count += GeometryHelpers.na_create_horizontal_segmented(face_entities, x_min, x_max, z_bot, y_mm, x_gaps)
            count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Vertical Mullion as a Gap-Clipped Pair
        # ------------------------------------------------------------
        # A mullion is rendered as TWO parallel vertical edges at
        # x = x_centre +/- (inner_rail_t / 2), spanning the inner
        # perimeter Z range and clipped at every cross-rail's Z band
        # so the joint with the cross-rail reads as a clean butt-joint.
        #
        # @param face_entities [Sketchup::Entities] Target group entities
        # @param layout [Hash] Layout from na_compute_layout
        # @param x_centre_mm [Numeric] Centre-line X of the mullion (mm)
        # @param cross_rails [Array<Hash>] Each entry: { :z_low, :z_high }
        # @param y_mm [Numeric] Y plane the linework lives on (mm)
        # @return [Integer] Number of edges added
        def self.na_draw_vertical_mullion_pair(face_entities, layout, x_centre_mm, cross_rails, y_mm)
            half_t = layout[:inner_rail_t] / 2.0
            z_min  = layout[:inner_z_min]
            z_max  = layout[:inner_z_max]
            z_gaps = na_cross_rails_to_z_gaps(cross_rails)
            x_lt   = x_centre_mm - half_t
            x_rt   = x_centre_mm + half_t

            count  = 0
            count += GeometryHelpers.na_create_vertical_segmented(face_entities, x_lt, z_min, z_max, y_mm, z_gaps)
            count += GeometryHelpers.na_create_vertical_segmented(face_entities, x_rt, z_min, z_max, y_mm, z_gaps)
            count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Joint Gap Computation
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert Mullion Specs to X-Range Gaps
        # ------------------------------------------------------------
        def self.na_mullions_to_x_gaps(mullions)
            return [] unless mullions.is_a?(Array) && !mullions.empty?
            mullions.map { |m| [m[:x_left].to_f, m[:x_right].to_f] }
                    .sort_by { |gap| gap[0] }
        end
        private_class_method :na_mullions_to_x_gaps
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Convert Cross-Rail Specs to Z-Range Gaps
        # ------------------------------------------------------------
        def self.na_cross_rails_to_z_gaps(cross_rails)
            return [] unless cross_rails.is_a?(Array) && !cross_rails.empty?
            cross_rails.map { |c| [c[:z_low].to_f, c[:z_high].to_f] }
                       .sort_by { |gap| gap[0] }
        end
        private_class_method :na_cross_rails_to_z_gaps
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PanelDesignFrame
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
