# =============================================================================
# NA INTERIOR DOOR CONFIGURATOR - GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__InteriorDoorConfigurator__GeometryHelpers__.rb
# NAMESPACE  : Na__InteriorDoorConfigurator
# MODULE     : Na__GeometryHelpers
# AUTHOR     : Noble Architecture
# PURPOSE    : Low-level primitives for door geometry creation
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Provides reusable primitives for creating individual door parts:
#       * Lining sections (jambs and head as solid boxes)
#       * Door panel solid (rectangular slab)
#       * 2D door swing arc (set 10mm above floor to avoid Z-fighting)
# - Mirrors the pattern of Na__WindowConfiguratorTool::Na__GeometryHelpers
#   (named groups, outward-facing normals, optional material).
# - All inputs are millimetres; outputs are SketchUp inches.
#
# COORDINATE SYSTEM:
# - Door is authored at the model origin with the lining outer face on Y=0.
# - X+ runs left -> right across the opening width.
# - Y+ runs front -> back through the wall depth.
# - Z+ runs upwards.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InteriorDoorConfigurator__DebugTools__'
require_relative 'Na__InteriorDoorConfigurator__TagManager__'

module Na__InteriorDoorConfigurator
    module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__InteriorDoorConfigurator::Na__DebugTools
        TagManager = Na__InteriorDoorConfigurator::Na__TagManager

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        # CONSTANTS | Unit Conversion
        # ------------------------------------------------------------
        NA_MM_TO_INCH = 1.0 / 25.4                                         # <-- Millimetre to inch conversion factor
        # ---------------------------------------------------------------

        # CONSTANTS | Door Swing Z-Lift
        # ------------------------------------------------------------
        # 2D door swings sit slightly above the floor to avoid Z-fighting
        # against floor faces in the SketchUp model.
        NA_DOOR_SWING_Z_LIFT_MM = 10                                       # <-- 10mm lift for door swing arcs
        # ---------------------------------------------------------------

        # CONSTANTS | Swing Arc Segment Count
        # ------------------------------------------------------------
        NA_DOOR_SWING_ARC_SEGMENTS = 24                                    # <-- Edges in the 90deg arc polyline
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Generic Box Helper
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert Millimetre Value to Inches
        # ------------------------------------------------------------
        def self.na_mm_to_inch(value_mm)
            value_mm.to_f * NA_MM_TO_INCH
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create a Named Box Group with Outward-Facing Normals
        # ------------------------------------------------------------
        # All eight corners are computed at final coordinates and the six
        # faces are reversed if their normals point inward. Optional
        # material is applied to both faces.
        #
        # @param entities [Sketchup::Entities] Parent entities collection
        # @param group_name [String] Name for the group
        # @param x_in, y_in, z_in [Float] Origin (inches)
        # @param width_in, depth_in, height_in [Float] Dimensions (inches)
        # @param material [Sketchup::Material, nil] Optional material
        # @return [Sketchup::Group] The created group
        def self.na_create_grouped_box(entities, group_name, x_in, y_in, z_in, width_in, depth_in, height_in, material = nil)
            return nil if width_in <= 0 || depth_in <= 0 || height_in <= 0

            group          = entities.add_group
            group.name     = group_name
            group_entities = group.entities

            p1 = Geom::Point3d.new(x_in,            y_in,            z_in)
            p2 = Geom::Point3d.new(x_in + width_in, y_in,            z_in)
            p3 = Geom::Point3d.new(x_in + width_in, y_in + depth_in, z_in)
            p4 = Geom::Point3d.new(x_in,            y_in + depth_in, z_in)
            p5 = Geom::Point3d.new(x_in,            y_in,            z_in + height_in)
            p6 = Geom::Point3d.new(x_in + width_in, y_in,            z_in + height_in)
            p7 = Geom::Point3d.new(x_in + width_in, y_in + depth_in, z_in + height_in)
            p8 = Geom::Point3d.new(x_in,            y_in + depth_in, z_in + height_in)

            box_centre = Geom::Point3d.new(
                x_in + width_in / 2.0,
                y_in + depth_in / 2.0,
                z_in + height_in / 2.0
            )

            faces = []
            faces << group_entities.add_face(p4, p3, p2, p1)               # <-- Bottom
            faces << group_entities.add_face(p5, p6, p7, p8)               # <-- Top
            faces << group_entities.add_face(p1, p2, p6, p5)               # <-- Front
            faces << group_entities.add_face(p3, p4, p8, p7)               # <-- Back
            faces << group_entities.add_face(p4, p1, p5, p8)               # <-- Left
            faces << group_entities.add_face(p2, p3, p7, p6)               # <-- Right

            faces.compact.each do |face|
                next unless face.valid?
                outward_vec = face.bounds.center - box_centre
                face.reverse! if outward_vec % face.normal < 0
            end

            if material
                faces.compact.each do |f|
                    next unless f.valid?
                    f.material      = material
                    f.back_material = material
                end
            end

            DebugTools.na_debug_geometry("Created box group '#{group_name}'")
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Door Lining Section Primitives
# -----------------------------------------------------------------------------

        # FUNCTION | Create a Single Door Lining Section (Jamb or Head)
        # ------------------------------------------------------------
        # Door lining sections are simple solid boxes whose dimensions
        # come from the structural opening + the lining thickness +
        # the wall depth. The same primitive serves jamb-L, jamb-R,
        # and the head section; the parent builder positions them.
        #
        # @param entities [Sketchup::Entities] Parent entities collection
        # @param origin_mm [Array<Numeric>] [x, y, z] origin in millimetres
        # @param size_mm [Array<Numeric>] [width, depth, height] in millimetres
        # @param name [String] Group name (e.g. "Na__Lining__Jamb_L")
        # @param material [Sketchup::Material, nil] Optional material
        # @param tag_role [Symbol] Tag role from TagManager (default :door_lining)
        # @return [Sketchup::Group, nil]
        def self.na_create_lining_section(entities, origin_mm, size_mm, name, material = nil, tag_role = :door_lining)
            x_in      = na_mm_to_inch(origin_mm[0])
            y_in      = na_mm_to_inch(origin_mm[1])
            z_in      = na_mm_to_inch(origin_mm[2])
            width_in  = na_mm_to_inch(size_mm[0])
            depth_in  = na_mm_to_inch(size_mm[1])
            height_in = na_mm_to_inch(size_mm[2])

            group = na_create_grouped_box(entities, name, x_in, y_in, z_in, width_in, depth_in, height_in, material)
            TagManager.na_apply_tag_to_entity(group, tag_role) if group
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Door Panel Primitive
# -----------------------------------------------------------------------------

        # FUNCTION | Create the Door Panel Solid
        # ------------------------------------------------------------
        # The panel is a single solid slab placed inside the lining.
        # Caller supplies origin (mm) at the panel's lower-front-left
        # corner and the panel's overall size (width x thickness x height).
        #
        # @param entities [Sketchup::Entities] Parent entities collection
        # @param origin_mm [Array<Numeric>] [x, y, z]
        # @param size_mm [Array<Numeric>] [width, thickness, height]
        # @param material [Sketchup::Material, nil]
        # @param tag_role [Symbol] Default :door_panel
        # @return [Sketchup::Group, nil]
        def self.na_create_door_panel_solid(entities, origin_mm, size_mm, material = nil, tag_role = :door_panel)
            x_in         = na_mm_to_inch(origin_mm[0])
            y_in         = na_mm_to_inch(origin_mm[1])
            z_in         = na_mm_to_inch(origin_mm[2])
            width_in     = na_mm_to_inch(size_mm[0])
            thickness_in = na_mm_to_inch(size_mm[1])
            height_in    = na_mm_to_inch(size_mm[2])

            group        = na_create_grouped_box(
                entities,
                "Na__DoorPanel__Solid",
                x_in, y_in, z_in,
                width_in, thickness_in, height_in,
                material
            )
            TagManager.na_apply_tag_to_entity(group, tag_role) if group
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | 2D Door Swing Primitive
# -----------------------------------------------------------------------------

        # FUNCTION | Build a 2D Door Swing Arc Group
        # ------------------------------------------------------------
        # Generates the L-shaped representation a draughtsman would draw:
        #     1. A straight edge representing the door panel projected open.
        #     2. A 90deg arc representing the swing path of the latch edge.
        # Both are placed at Z = NA_DOOR_SWING_Z_LIFT_MM (default 10mm)
        # and tagged with the :door_swing role so they can be toggled
        # off in SketchUp/Layout.
        #
        # @param entities [Sketchup::Entities] Parent entities collection
        # @param hinge_point_mm [Array<Numeric>] [x, y] in millimetres
        # @param swing_radius_mm [Numeric] Radius of the swing arc (= panel width)
        # @param side [Symbol] :left or :right (which side the door is hinged)
        # @param direction [Symbol] :inward or :outward (which face it swings to)
        # @param tag_role [Symbol] Default :door_swing
        # @return [Sketchup::Group, nil] Group containing the swing edges
        def self.na_build_2d_swing_arc(entities, hinge_point_mm, swing_radius_mm, side, direction, tag_role = :door_swing)
            return nil if swing_radius_mm <= 0

            group       = entities.add_group
            group.name  = "Na__DoorSwing__2D"
            group_ents  = group.entities

            hinge_in    = Geom::Point3d.new(
                na_mm_to_inch(hinge_point_mm[0]),
                na_mm_to_inch(hinge_point_mm[1]),
                na_mm_to_inch(NA_DOOR_SWING_Z_LIFT_MM)
            )
            radius_in   = na_mm_to_inch(swing_radius_mm)

            angles      = na_compute_swing_arc_angles(side, direction)

            arc_pts     = na_compute_arc_points(hinge_in, radius_in, angles[:start], angles[:sweep], NA_DOOR_SWING_ARC_SEGMENTS)
            (arc_pts.length - 1).times do |i|
                group_ents.add_line(arc_pts[i], arc_pts[i + 1])
            end

            open_end_pt = arc_pts.first                                    # <-- Latch position when fully open
            group_ents.add_line(hinge_in, open_end_pt)                     # <-- Door panel projection edge

            TagManager.na_apply_tag_to_entity(group, tag_role)
            DebugTools.na_debug_geometry("Built 2D swing arc (side=#{side}, direction=#{direction}, r=#{swing_radius_mm}mm)")
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Swing Geometry Math
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Compute Start Angle and Sweep Direction for a Swing
        # ------------------------------------------------------------
        # The swing always covers 90 degrees. Hand and direction control
        # which quadrant the arc sits in (in plan view, with X+ right and
        # Y+ into the room).
        def self.na_compute_swing_arc_angles(side, direction)
            side_sym      = side.is_a?(Symbol) ? side : side.to_s.downcase.to_sym
            direction_sym = direction.is_a?(Symbol) ? direction : direction.to_s.downcase.to_sym

            quadrant = case [side_sym, direction_sym]
                       when [:left,  :inward]  then  90.0                  # <-- Hinge left, swings into room (Y+)
                       when [:right, :inward]  then  90.0                  # <-- Hinge right, swings into room (Y+)
                       when [:left,  :outward] then 270.0                  # <-- Hinge left, swings outward (Y-)
                       when [:right, :outward] then 270.0                  # <-- Hinge right, swings outward (Y-)
                       else                          90.0
                       end

            start_angle  = if side_sym == :left
                               quadrant                                    # <-- Latch starts on +X side
                           else
                               quadrant - 90.0                             # <-- Latch starts on -X side
                           end

            sweep_deg    = (side_sym == :left) ? -90.0 : 90.0              # <-- Sweep direction follows hand
            { :start => start_angle, :sweep => sweep_deg }
        end
        private_class_method :na_compute_swing_arc_angles
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compute Points Along an Arc on the XY Plane
        # ------------------------------------------------------------
        # @param centre [Geom::Point3d] Centre of the arc
        # @param radius [Float] Radius (inches)
        # @param start_deg [Float] Start angle (degrees, 0 = +X axis)
        # @param sweep_deg [Float] Sweep (degrees, signed)
        # @param segments [Integer] Number of segments
        # @return [Array<Geom::Point3d>] segments+1 points
        def self.na_compute_arc_points(centre, radius, start_deg, sweep_deg, segments)
            points = []
            (0..segments).each do |i|
                t       = i.to_f / segments
                angle   = (start_deg + sweep_deg * t) * Math::PI / 180.0
                px      = centre.x + radius * Math.cos(angle)
                py      = centre.y + radius * Math.sin(angle)
                points << Geom::Point3d.new(px, py, centre.z)
            end
            points
        end
        private_class_method :na_compute_arc_points
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryHelpers
end # module Na__InteriorDoorConfigurator

# =============================================================================
# END OF FILE
# =============================================================================
