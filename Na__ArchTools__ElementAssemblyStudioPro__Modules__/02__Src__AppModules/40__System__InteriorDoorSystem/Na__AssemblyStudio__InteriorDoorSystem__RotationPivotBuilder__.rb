# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - ROTATION PIVOT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__RotationPivotBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__RotationPivotBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Populate the empty ROT001__RotationPoint__DoorHingeCentre group
#              with visible red-dashed debug geometry (vertical hinge axis line,
#              50x50mm crosshairs at both ends, and a swing-direction arrow)
#              consumed by the downstream TrueVision3D click-to-open animation.
# CREATED    : 03-May-2026
#
# DESCRIPTION:
# - The TrueVision3D Three.js importer reads
#   `rotObject.position` (the ROT group's local origin) as the door
#   rotation pivot. The composer now places ROT at the ComponentDefinition
#   root level (sibling of the ADR groups, NOT inside them) so the SketchUp
#   author can grab the helper without drilling into the door panel. The
#   group's transformation/origin must remain at the hinge centre - the
#   composer ensures this via na_translate_rot_marker_to_hinge before
#   calling this builder.
# - All geometry is drawn in LOCAL coordinates relative to the ROT group's
#   origin: hinge centre = (0, 0, 0). This makes the helper invariant under
#   the parent component's world placement.
# - As the FINAL build step every edge is painted red via
#   Na__EdgeColourManager.na_apply_edge_colour_to_group with MTE id
#   `MTE201__LineColour__Red`. This mirrors the dark-grey edge-colour
#   application used by Na__PanelDesignBuilder for door panel design
#   linework so the helper looks unambiguously red in the SketchUp model
#   regardless of any colour-by-tag display option.
# - All edges also live on the tag `02__DoorHelpers__RotationPivots`
#   (numeric prefix `02` is in the GLB exporter skipRanges, so the helper
#   never reaches production GLBs). The tag itself is red and dashed;
#   toggle its visibility to hide pivots in clean SketchUp views.
#
# COORDINATE SYSTEM (ROT-local, mirrors door-local):
# - Origin       = hinge axis on the inside corner of the hinge-side jamb.
# - X+           = along the wall (toward the latch).
# - Y+           = through the wall depth.
# - Z+           = upwards.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__RotationPivotBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        TagManager        = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        GeometryHelpers   = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Helper Geometry Dimensions (millimetres)
# -----------------------------------------------------------------------------

        # CONSTANTS | Pivot Line Inset From Both Ends Of The Hinge-Side Jamb
        # ------------------------------------------------------------
        NA_PIVOT_END_INSET_MM           = 100                           # <-- Inset of vertical line ends from jamb top + bottom
        # ---------------------------------------------------------------

        # CONSTANTS | Crosshair Dimensions At Each End Of The Vertical Line
        # ------------------------------------------------------------
        NA_CROSSHAIR_HALF_LENGTH_MM     = 25                            # <-- Half-extent of the 50x50 mm '+' on the XY plane
        # ---------------------------------------------------------------

        # CONSTANTS | Swing-Direction Arrow Geometry
        # ------------------------------------------------------------
        NA_SWING_ARROW_RADIUS_MM        = 100                           # <-- Arc radius for the rotation indicator
        NA_SWING_ARROW_SEGMENT_COUNT    = 8                             # <-- Polyline segments for the 90deg arc
        NA_SWING_ARROW_HEAD_LENGTH_MM   = 25                            # <-- Length of each arrowhead 'V' edge
        # ---------------------------------------------------------------

        # CONSTANTS | Red Edge Colour For The Pivot Helper Linework
        # ------------------------------------------------------------
        # Resolved against the live MTE edge-material library through
        # Na__EdgeColourManager. Mirrors the dark-grey edge colour used
        # by Na__PanelDesignBuilder for door panel design linework.
        NA_HELPER_EDGE_COLOUR_ID        = "MTE201__LineColour__Red".freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build The Pivot Helper Inside The ROT Group
        # ------------------------------------------------------------
        # Adds the vertical hinge axis line, two endpoint crosshairs, and
        # the swing-direction arrow to the ROT group's entities, all in the
        # group's local coordinate space (hinge = 0, 0, 0). The ROT group
        # MUST already be translated to the hinge centre by the composer.
        #
        # @param rot_group [Sketchup::Group] The empty ROT marker group
        # @param config [Hash] Na__DoorConfiguration block
        # @param leaf [Hash, nil] Optional leaf descriptor; its forced hinge
        #   side drives the swing-direction arrow for double-door leaves.
        # @return [Boolean] True on success, false otherwise
        def self.na_build_pivot_helper(rot_group, config, leaf = nil)
            return false unless rot_group && rot_group.valid?

            opening_h_mm  = config["Na__DoorConfig__OpeningHeight_mm"].to_f
            lining_t_mm   = config["Na__DoorConfig__LiningThickness_mm"].to_f

            bottom_z_mm   = NA_PIVOT_END_INSET_MM
            top_z_mm      = (opening_h_mm - lining_t_mm) - NA_PIVOT_END_INSET_MM
            return false if top_z_mm <= bottom_z_mm

            entities      = rot_group.entities

            na_draw_vertical_axis_line(entities, bottom_z_mm, top_z_mm)
            na_draw_crosshair_at(entities, bottom_z_mm)
            na_draw_crosshair_at(entities, top_z_mm)
            na_draw_swing_direction_arrow(entities, top_z_mm, config, leaf)

            na_paint_helper_edges_red(rot_group)

            DebugTools.na_debug_geometry(
                "Built rotation pivot helper (hinge axis z=#{bottom_z_mm.round}..#{top_z_mm.round}mm)"
            )
            true
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry Construction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Draw The Vertical Hinge Axis Line At Local X=0, Y=0
        # ------------------------------------------------------------
        def self.na_draw_vertical_axis_line(entities, bottom_z_mm, top_z_mm)
            p0 = na_local_point_in(0.0, 0.0, bottom_z_mm)
            p1 = na_local_point_in(0.0, 0.0, top_z_mm)
            edge = entities.add_line(p0, p1)
            na_apply_helper_tag(edge)
        end
        private_class_method :na_draw_vertical_axis_line
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Draw A 50x50mm '+' Crosshair On The XY Plane At Z
        # ------------------------------------------------------------
        # Two perpendicular edges centred on the hinge axis, both lying on
        # the horizontal plane at the supplied Z height.
        def self.na_draw_crosshair_at(entities, z_mm)
            half = NA_CROSSHAIR_HALF_LENGTH_MM

            x_edge_p0 = na_local_point_in(-half, 0.0, z_mm)
            x_edge_p1 = na_local_point_in(+half, 0.0, z_mm)
            x_edge    = entities.add_line(x_edge_p0, x_edge_p1)
            na_apply_helper_tag(x_edge)

            y_edge_p0 = na_local_point_in(0.0, -half, z_mm)
            y_edge_p1 = na_local_point_in(0.0, +half, z_mm)
            y_edge    = entities.add_line(y_edge_p0, y_edge_p1)
            na_apply_helper_tag(y_edge)
        end
        private_class_method :na_draw_crosshair_at
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Draw The Swing-Direction Arrow At The Top Crosshair Z
        # ------------------------------------------------------------
        # Quarter-circle arc on the XY plane from the closed-latch direction
        # to the open-latch direction, with a 'V' arrowhead at the open end
        # that points tangent to the arc (i.e. in the direction of rotation).
        def self.na_draw_swing_direction_arrow(entities, z_mm, config, leaf = nil)
            angles = na_resolve_swing_angles(config, leaf)
            return unless angles

            arc_pts_in = na_compute_arrow_arc_points(angles[:start_deg], angles[:sweep_deg], z_mm)
            return if arc_pts_in.length < 2

            na_draw_polyline_edges(entities, arc_pts_in)
            na_draw_arrowhead_at_open_end(entities, arc_pts_in)
        end
        private_class_method :na_draw_swing_direction_arrow
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compute Polyline Points For The Swing Arrow Arc
        # ------------------------------------------------------------
        # Returns Geom::Point3d objects in inches at the supplied Z height.
        # The arc has NA_SWING_ARROW_SEGMENT_COUNT + 1 vertices.
        def self.na_compute_arrow_arc_points(start_deg, sweep_deg, z_mm)
            radius_in = GeometryHelpers.na_mm_to_inch(NA_SWING_ARROW_RADIUS_MM)
            z_in      = GeometryHelpers.na_mm_to_inch(z_mm)
            segments  = NA_SWING_ARROW_SEGMENT_COUNT
            points    = []

            (0..segments).each do |i|
                t       = i.to_f / segments
                angle   = (start_deg + sweep_deg * t) * Math::PI / 180.0
                px_in   = radius_in * Math.cos(angle)
                py_in   = radius_in * Math.sin(angle)
                points << Geom::Point3d.new(px_in, py_in, z_in)
            end

            points
        end
        private_class_method :na_compute_arrow_arc_points
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Add Consecutive Edges Between An Ordered Point List
        # ------------------------------------------------------------
        def self.na_draw_polyline_edges(entities, points)
            (points.length - 1).times do |i|
                edge = entities.add_line(points[i], points[i + 1])
                na_apply_helper_tag(edge)
            end
        end
        private_class_method :na_draw_polyline_edges
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Draw The 'V' Arrowhead At The Last Point Of The Arc
        # ------------------------------------------------------------
        # The two arrowhead edges fan back from the tip along the arc's
        # tangent so the arrow visually points in the direction of rotation.
        def self.na_draw_arrowhead_at_open_end(entities, arc_pts_in)
            tip      = arc_pts_in.last
            previous = arc_pts_in[-2]

            tangent  = na_normalise_xy_vector(tip.x - previous.x, tip.y - previous.y)
            return unless tangent

            perp_x   = -tangent[1]
            perp_y   =  tangent[0]
            head_in  = GeometryHelpers.na_mm_to_inch(NA_SWING_ARROW_HEAD_LENGTH_MM)

            back_x   = -tangent[0]
            back_y   = -tangent[1]

            wing_a_x = (back_x + perp_x) * head_in / Math.sqrt(2.0)
            wing_a_y = (back_y + perp_y) * head_in / Math.sqrt(2.0)
            wing_b_x = (back_x - perp_x) * head_in / Math.sqrt(2.0)
            wing_b_y = (back_y - perp_y) * head_in / Math.sqrt(2.0)

            wing_a   = Geom::Point3d.new(tip.x + wing_a_x, tip.y + wing_a_y, tip.z)
            wing_b   = Geom::Point3d.new(tip.x + wing_b_x, tip.y + wing_b_y, tip.z)

            edge_a = entities.add_line(tip, wing_a)
            edge_b = entities.add_line(tip, wing_b)
            na_apply_helper_tag(edge_a)
            na_apply_helper_tag(edge_b)
        end
        private_class_method :na_draw_arrowhead_at_open_end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Math And Coordinate Utilities
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve Closed -> Open Sweep Angles For The Door
        # ------------------------------------------------------------
        # Mirrors the convention used by the existing 2D swing arc:
        #   * Left-hand door  -> closed latch on +X (angle   0 deg).
        #   * Right-hand door -> closed latch on -X (angle 180 deg).
        #   * Inward swing    -> open latch on -Y (angle -90 deg).
        #   * Outward swing   -> open latch on +Y (angle +90 deg).
        # The arc is drawn START=closed_angle, END=open_angle so the arrow
        # tip naturally lands on the open-latch direction.
        def self.na_resolve_swing_angles(config, leaf = nil)
            swing_side      = ((leaf && leaf[:swing_side]) ? leaf[:swing_side] : (config["Na__DoorConfig__SwingSide"] || "Left")).to_s.downcase.to_sym
            swing_direction = (config["Na__DoorConfig__SwingDirection"] || "Inward").to_s.downcase.to_sym

            closed_deg      = (swing_side == :left)     ?   0.0 : 180.0
            open_y_sign     = (swing_direction == :inward) ? -1.0 :   1.0
            open_deg        = open_y_sign * 90.0

            sweep_deg       = open_deg - closed_deg
            sweep_deg      -= 360.0 if sweep_deg >  180.0
            sweep_deg      += 360.0 if sweep_deg < -180.0

            { :start_deg => closed_deg, :sweep_deg => sweep_deg }
        end
        private_class_method :na_resolve_swing_angles
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build A SketchUp Point In Inches From mm-Local Coords
        # ------------------------------------------------------------
        def self.na_local_point_in(x_mm, y_mm, z_mm)
            Geom::Point3d.new(
                GeometryHelpers.na_mm_to_inch(x_mm),
                GeometryHelpers.na_mm_to_inch(y_mm),
                GeometryHelpers.na_mm_to_inch(z_mm)
            )
        end
        private_class_method :na_local_point_in
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Normalise A 2D Vector In The XY Plane
        # ------------------------------------------------------------
        # Returns nil if the input length is effectively zero so callers
        # can short-circuit safely.
        def self.na_normalise_xy_vector(dx, dy)
            length = Math.sqrt(dx * dx + dy * dy)
            return nil if length < 1.0e-9
            [dx / length, dy / length]
        end
        private_class_method :na_normalise_xy_vector
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Tagging & Edge Colour
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Tag An Edge With The :door_helpers Role
        # ------------------------------------------------------------
        # The TagManager resolves :door_helpers to the
        # `02__DoorHelpers__RotationPivots` tag and applies the red colour
        # plus the dashed line style declared in the DataLib Tags JSON.
        def self.na_apply_helper_tag(edge)
            return unless edge && edge.respond_to?(:layer=)
            TagManager.na_apply_tag_to_entity(edge, :door_helpers)
        end
        private_class_method :na_apply_helper_tag
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Paint Every Helper Edge With The Red MTE Colour
        # ------------------------------------------------------------
        # Mirrors how Na__PanelDesignBuilder finalises panel design
        # linework with EdgeColourManager.na_apply_edge_colour_to_group:
        # call this AFTER all geometry has been added so the recursive
        # walker hits every edge added by the helpers above. The MTE
        # material is created on the active model on first use and
        # cached for subsequent doors in the session.
        def self.na_paint_helper_edges_red(rot_group)
            return unless rot_group && rot_group.respond_to?(:valid?) && rot_group.valid?
            EdgeColourManager.na_apply_edge_colour_to_group(rot_group, NA_HELPER_EDGE_COLOUR_ID)
        end
        private_class_method :na_paint_helper_edges_red
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__RotationPivotBuilder
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
