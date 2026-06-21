# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
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
# - Mirrors the pattern of Na__AssemblyStudio::Na__WindowSystem::Na__GeometryHelpers
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
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        TagManager = Na__AssemblyStudio::Na__AppUtils::Na__TagManager

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
# REGION | Leaf Composition (Single vs Double Door)
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve the Door Leaves to Build (Single or Double)
        # ------------------------------------------------------------
        # SINGLE SOURCE OF TRUTH for how many door leaves an opening
        # contains and where each one sits. Every leaf-specific builder
        # (panel, swing, handles, panel design, MOD/ROT composition)
        # consumes the leaf hashes returned here so the 3D model and the
        # 2D preview stay in lockstep.
        #
        #   * Single door -> one full-width leaf hinged on SwingSide.
        #   * Double door -> two flush-meeting half-width leaves; the
        #     left leaf hinges on the left jamb, the right leaf on the
        #     right jamb, both swinging the same SwingDirection. The
        #     latch edges meet at the opening centre (no gap).
        #
        # Leaf hash shape (all distances in millimetres):
        #   {
        #     :index       => 1-based leaf number (drives MOD/ROT names),
        #     :swing_side  => "left" | "right" (effective hinge side),
        #     :origin_x_mm => panel lower-front-left X,
        #     :leaf_w_mm   => leaf width,
        #     :hinge_x_mm  => hinge pivot X
        #   }
        #
        # @param config [Hash] Na__DoorConfiguration block
        # @return [Array<Hash>] one or two leaf descriptors
        def self.na_compute_leaves(config)
            opening_w_mm = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            lining_t_mm  = config["Na__DoorConfig__LiningThickness_mm"].to_f
            inner_w_mm   = opening_w_mm - 2 * lining_t_mm
            door_type    = (config["Na__DoorConfig__DoorType"] || "Single").to_s.downcase

            if door_type == "double"
                leaf_w_mm = inner_w_mm / 2.0                                # <-- Flush meeting leaves, no centre gap
                [
                    {
                        :index       => 1,
                        :swing_side  => "left",
                        :origin_x_mm => lining_t_mm,
                        :leaf_w_mm   => leaf_w_mm,
                        :hinge_x_mm  => lining_t_mm
                    },
                    {
                        :index       => 2,
                        :swing_side  => "right",
                        :origin_x_mm => lining_t_mm + leaf_w_mm,
                        :leaf_w_mm   => leaf_w_mm,
                        :hinge_x_mm  => opening_w_mm - lining_t_mm
                    }
                ]
            else
                swing_side = (config["Na__DoorConfig__SwingSide"] || "Left").to_s.downcase
                hinge_x_mm = (swing_side == "left") ? lining_t_mm : (opening_w_mm - lining_t_mm)
                [
                    {
                        :index       => 1,
                        :swing_side  => swing_side,
                        :origin_x_mm => lining_t_mm,
                        :leaf_w_mm   => inner_w_mm,
                        :hinge_x_mm  => hinge_x_mm
                    }
                ]
            end
        end
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

        # HELPER FUNCTION | Resolve Panel Front-Face Y Origin (mm)
        # ------------------------------------------------------------
        # Single source of truth for where the door panel sits within
        # the wall depth based on SwingDirection.
        #
        # Standard door architecture: the hinge is mounted at one corner
        # of the lining reveal, and the door panel's "outer face" (the
        # face that is flush with the hinge side of the lining) always
        # sits on the hinge-side face of the lining. The panel never
        # sits inside the lining depth and never swings through the
        # reveal - it opens cleanly away from the lining.
        #
        #   * Inward  opening -> hinge on the NEAR (front / room) face
        #     of the lining. Panel closed flush with that near face
        #     (Y = face_offset). Panel swings away from the lining
        #     into the room (-Y direction) when opened.
        #   * Outward opening -> hinge on the FAR (back / exterior)
        #     face of the lining. Panel closed flush with that far
        #     face (Y = face_offset + wall_depth - panel_t). Panel
        #     swings away from the lining into the exterior (+Y
        #     direction) when opened.
        #   * Any other / missing value -> centred in the wall depth
        #     (legacy fallback).
        #
        # Left/Right handing is orthogonal to this and flips the hinge
        # between the left and right jamb; it does not affect which
        # face of the lining the panel is flush with.
        #
        # Consumers: GeometryBuilders (panel + swing), HandleBuilder3D
        # (handle Y), DoorAssemblyComposer (hinge Y + open-state rotation).
        #
        # @param config [Hash] Na__DoorConfiguration block
        # @return [Float] Panel front-face Y in millimetres
        def self.na_panel_y_origin_mm(config)
            wall_depth_mm   = config["Na__DoorConfig__WallDepth_mm"].to_f
            panel_t_mm      = config["Na__DoorConfig__PanelThickness_mm"].to_f
            face_offset_mm  = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            swing_direction = config["Na__DoorConfig__SwingDirection"].to_s.downcase

            case swing_direction
            when "inward"
                face_offset_mm                                        # <-- Flush with NEAR / front / room face (hinge on near side)
            when "outward"
                face_offset_mm + (wall_depth_mm - panel_t_mm)         # <-- Flush with FAR / back / exterior face (hinge on far side)
            else
                face_offset_mm + (wall_depth_mm - panel_t_mm) / 2.0   # <-- Centred fallback
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve Panel Centre Y (mm) - Derived from Origin
        # ------------------------------------------------------------
        def self.na_panel_centre_y_mm(config)
            panel_t_mm = config["Na__DoorConfig__PanelThickness_mm"].to_f
            na_panel_y_origin_mm(config) + (panel_t_mm / 2.0)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve Hinge Pivot Y Origin (mm)
        # ------------------------------------------------------------
        # Returns the Y coordinate of the door's hinge pivot axis - i.e.
        # the Y of the wall face the hinge sits on.  This is DIFFERENT
        # from the panel front-face Y for outward-swinging doors:
        #
        #   * Inward  opening -> hinge on NEAR wall face; the panel's
        #     front face is also the near face, so hinge_y = face_offset
        #     (same as na_panel_y_origin_mm).
        #   * Outward opening -> hinge on FAR wall face; the panel's
        #     front face is the ROOM-facing face, so hinge_y sits one
        #     panel_t beyond the panel origin, at
        #     face_offset + wall_depth (the panel's back face, flush
        #     with the far wall face).
        #   * Any other / missing value -> centred in wall depth
        #     (legacy fallback).
        #
        # Consumers that must pivot around the hinge axis:
        #   * GeometryBuilders.na_build_swing (2D swing arc on floor)
        #   * DoorAssemblyComposer.na_translate_rot_marker_to_hinge
        #     (ROT marker group origin)
        #   * DoorAssemblyComposer.na_compute_open_rotation_transform
        #     (open-state copy rotation pivot)
        #
        # Panel geometry origin / handle centre-line consumers must
        # continue to use na_panel_y_origin_mm / na_panel_centre_y_mm.
        #
        # @param config [Hash] Na__DoorConfiguration block
        # @return [Float] Hinge pivot Y in millimetres
        def self.na_hinge_y_origin_mm(config)
            wall_depth_mm   = config["Na__DoorConfig__WallDepth_mm"].to_f
            face_offset_mm  = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            swing_direction = config["Na__DoorConfig__SwingDirection"].to_s.downcase

            case swing_direction
            when "inward"
                face_offset_mm                                        # <-- Near wall face (= panel front face)
            when "outward"
                face_offset_mm + wall_depth_mm                        # <-- Far wall face (= panel back face)
            else
                face_offset_mm + wall_depth_mm / 2.0                  # <-- Centred fallback
            end
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
        # Returns the {start, sweep} angles (degrees, math convention with
        # 0 = +X axis) used by na_compute_arc_points to plot the 90 deg
        # quarter-circle arc for the door swing.
        #
        # Door-local convention:
        #   * Closed latch sits on +X for Left-hand doors and -X for
        #     Right-hand doors.
        #   * Inward swings rotate the latch to -Y (room side of wall).
        #   * Outward swings rotate the latch to +Y (back side of wall).
        #
        # arc_pts.first must always be the OPEN-latch position because
        # na_build_2d_swing_arc consumes it as the panel-projection edge.
        def self.na_compute_swing_arc_angles(side, direction)
            side_sym      = side.is_a?(Symbol)      ? side      : side.to_s.downcase.to_sym
            direction_sym = direction.is_a?(Symbol) ? direction : direction.to_s.downcase.to_sym

            closed_angle  = (side_sym == :left) ? 0.0 : 180.0              # <-- Closed-latch direction from hinge
            open_y_sign   = (direction_sym == :inward) ? -1.0 : 1.0        # <-- Inward swings toward -Y
            open_angle    = open_y_sign * 90.0                             # <-- Open-latch direction from hinge

            sweep_deg     = closed_angle - open_angle                      # <-- Sweep from open to closed
            sweep_deg    -= 360.0 if sweep_deg >  180.0                    # <-- Normalise to shortest path
            sweep_deg    += 360.0 if sweep_deg < -180.0

            { :start => open_angle, :sweep => sweep_deg }
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

# -----------------------------------------------------------------------------
# REGION | XZ-Plane Linework Primitives (Panel Design Subsystem)
# -----------------------------------------------------------------------------

        # FUNCTION | Create a Single Edge in the XZ Plane at a Constant Y
        # ------------------------------------------------------------
        # Used by the door panel design builders to draw decorative
        # linework on the panel face. All inputs are millimetres;
        # conversion to inches happens here so callers stay metric.
        # Edges shorter than ~0.001mm are skipped to avoid SketchUp
        # creating zero-length entities.
        #
        # @param entities [Sketchup::Entities] Target entities collection
        # @param x0_mm, z0_mm [Numeric] Start point (mm)
        # @param x1_mm, z1_mm [Numeric] End point (mm)
        # @param y_mm [Numeric] Y plane the line lives on (mm)
        # @return [Sketchup::Edge, nil]
        def self.na_create_xz_line(entities, x0_mm, z0_mm, x1_mm, z1_mm, y_mm)
            dx = (x1_mm - x0_mm).to_f
            dz = (z1_mm - z0_mm).to_f
            return nil if (dx.abs + dz.abs) < 0.001

            p0 = Geom::Point3d.new(na_mm_to_inch(x0_mm), na_mm_to_inch(y_mm), na_mm_to_inch(z0_mm))
            p1 = Geom::Point3d.new(na_mm_to_inch(x1_mm), na_mm_to_inch(y_mm), na_mm_to_inch(z1_mm))
            edges = entities.add_edges(p0, p1)
            edges.first if edges
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Horizontal Line as Multiple Segments, Skipping Gaps
        # ------------------------------------------------------------
        # Architectural joint convention: where one rail/mullion crosses
        # another, the inner segment is removed so the joint reads as a
        # clean butt-joint. This helper walks left-to-right, skipping any
        # interval where a perpendicular element is in the way.
        #
        # @param entities [Sketchup::Entities] Target entities collection
        # @param x0_mm [Numeric] Line start X (mm)
        # @param x1_mm [Numeric] Line end X (mm)
        # @param z_mm [Numeric] Constant Z of the line (mm)
        # @param y_mm [Numeric] Y plane the line lives on (mm)
        # @param x_gaps [Array<Array<Numeric>>] Sorted, non-overlapping
        #   [x_start, x_end] pairs to skip
        # @return [Integer] Count of edges drawn
        def self.na_create_horizontal_segmented(entities, x0_mm, x1_mm, z_mm, y_mm, x_gaps = [])
            return 0 if x1_mm <= x0_mm
            cursor = x0_mm.to_f
            count  = 0
            (x_gaps || []).each do |gap|
                gap_start = gap[0].to_f
                gap_end   = gap[1].to_f
                next if gap_end <= cursor
                break if gap_start >= x1_mm
                if gap_start > cursor
                    count += 1 if na_create_xz_line(entities, cursor, z_mm, gap_start, z_mm, y_mm)
                end
                cursor = gap_end if gap_end > cursor
            end
            if cursor < x1_mm
                count += 1 if na_create_xz_line(entities, cursor, z_mm, x1_mm, z_mm, y_mm)
            end
            count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Vertical Line as Multiple Segments, Skipping Gaps
        # ------------------------------------------------------------
        # Vertical equivalent of na_create_horizontal_segmented. Walks
        # bottom-to-top through z_gaps and draws the visible segments.
        #
        # @param entities [Sketchup::Entities] Target entities collection
        # @param x_mm [Numeric] Constant X of the line (mm)
        # @param z0_mm [Numeric] Line start Z (mm)
        # @param z1_mm [Numeric] Line end Z (mm)
        # @param y_mm [Numeric] Y plane the line lives on (mm)
        # @param z_gaps [Array<Array<Numeric>>] Sorted, non-overlapping
        #   [z_start, z_end] pairs to skip
        # @return [Integer] Count of edges drawn
        def self.na_create_vertical_segmented(entities, x_mm, z0_mm, z1_mm, y_mm, z_gaps = [])
            return 0 if z1_mm <= z0_mm
            cursor = z0_mm.to_f
            count  = 0
            (z_gaps || []).each do |gap|
                gap_start = gap[0].to_f
                gap_end   = gap[1].to_f
                next if gap_end <= cursor
                break if gap_start >= z1_mm
                if gap_start > cursor
                    count += 1 if na_create_xz_line(entities, x_mm, cursor, x_mm, gap_start, y_mm)
                end
                cursor = gap_end if gap_end > cursor
            end
            if cursor < z1_mm
                count += 1 if na_create_xz_line(entities, x_mm, cursor, x_mm, z1_mm, y_mm)
            end
            count
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryHelpers
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
