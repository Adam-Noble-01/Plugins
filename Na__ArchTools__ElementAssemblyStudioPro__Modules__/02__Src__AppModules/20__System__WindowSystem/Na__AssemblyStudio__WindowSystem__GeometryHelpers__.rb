# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__GeometryHelpers__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__GeometryHelpers
# AUTHOR     : Noble Architecture
# PURPOSE    : Helper functions for creating grouped window geometry elements
# CREATED    : 2026
# VERSION    : 0.2.0
#
# DESCRIPTION:
# - Provides helper functions for creating named groups for window elements
# - Each window piece (rail, stile, mullion, etc.) is wrapped in its own group
# - Enables easy identification and manipulation of individual elements
# - Supports face orientation correction for all created geometry
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
# - Group names follow pattern: "Na_{ElementType}_{SubPart}"
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Group Creation Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Create Named Group
        # ------------------------------------------------------------
        # Creates a named group and yields to a block for adding geometry.
        # 
        # @param entities [Sketchup::Entities] Parent entities collection
        # @param name [String] Name for the group
        # @yield [Sketchup::Entities] The group's entities for adding geometry
        # @return [Sketchup::Group] The created group
        def self.na_create_named_group(entities, name)
            group = entities.add_group
            group.name = name
            yield group.entities if block_given?
            DebugTools.na_debug_geometry("Created group: #{name}")
            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Box in Named Group
        # ------------------------------------------------------------
        # Creates a box geometry inside a named group.
        # Uses the correct winding order for outward-facing normals.
        # 
        # @param entities [Sketchup::Entities] Parent entities collection
        # @param group_name [String] Name for the group
        # @param x [Float] X position (left edge)
        # @param y [Float] Y position (front edge)
        # @param z [Float] Z position (bottom edge)
        # @param width [Float] Width in X direction
        # @param depth [Float] Depth in Y direction
        # @param height [Float] Height in Z direction
        # @param material [Sketchup::Material] Material to apply
        # @return [Sketchup::Group] The created group containing the box
        def self.na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
            return nil if width <= 0 || depth <= 0 || height <= 0
            
            group = entities.add_group
            group.name = group_name
            group_entities = group.entities
            
            # Define all 8 corners of the box at FINAL coordinates
            p1 = Geom::Point3d.new(x, y, z)                          # Front-left-bottom
            p2 = Geom::Point3d.new(x + width, y, z)                  # Front-right-bottom
            p3 = Geom::Point3d.new(x + width, y + depth, z)          # Back-right-bottom
            p4 = Geom::Point3d.new(x, y + depth, z)                  # Back-left-bottom
            p5 = Geom::Point3d.new(x, y, z + height)                 # Front-left-top
            p6 = Geom::Point3d.new(x + width, y, z + height)         # Front-right-top
            p7 = Geom::Point3d.new(x + width, y + depth, z + height) # Back-right-top
            p8 = Geom::Point3d.new(x, y + depth, z + height)         # Back-left-top
            
            # Calculate box center for normal direction checking
            center = Geom::Point3d.new(x + width/2.0, y + depth/2.0, z + height/2.0)
            
            # Create all 6 faces - CCW winding when viewed from outside for outward normals
            faces = []
            faces << group_entities.add_face(p4, p3, p2, p1)  # Bottom
            faces << group_entities.add_face(p5, p6, p7, p8)  # Top
            faces << group_entities.add_face(p1, p2, p6, p5)  # Front
            faces << group_entities.add_face(p3, p4, p8, p7)  # Back
            faces << group_entities.add_face(p4, p1, p5, p8)  # Left
            faces << group_entities.add_face(p2, p3, p7, p6)  # Right
            
            # Verify and fix face orientations - ensure normals point outward
            faces.compact.each do |face|
                next unless face.valid?
                face_center = face.bounds.center
                face_normal = face.normal
                outward_vec = face_center - center
                face.reverse! if outward_vec % face_normal < 0
            end
            
            # Apply material
            if material
                faces.compact.each do |f|
                    next unless f.valid?
                    f.material = material
                    f.back_material = material
                end
            end
            
            DebugTools.na_debug_geometry("Created grouped box: #{group_name}")
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Element Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Create Frame Stile (Vertical Member)
        # ------------------------------------------------------------
        def self.na_create_frame_stile(entities, side, x, y, z, thickness, depth, height, material)
            group_name = "Na_Frame_#{side}_Stile"
            na_create_grouped_box(entities, group_name, x, y, z, thickness, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Frame Rail (Horizontal Member)
        # ------------------------------------------------------------
        def self.na_create_frame_rail(entities, position, x, y, z, width, depth, thickness, material)
            group_name = "Na_Frame_#{position}_Rail"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, thickness, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Mullion
        # ------------------------------------------------------------
        def self.na_create_mullion(entities, index, x, y, z, width, depth, height, material)
            group_name = "Na_Mullion_#{index}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Transom
        # ------------------------------------------------------------
        def self.na_create_transom(entities, identifier, x, y, z, width, depth, height, material)
            group_name = "Na_Transom_#{identifier}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Casement Element Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Create Casement Stile (Vertical Member)
        # ------------------------------------------------------------
        def self.na_create_casement_stile(entities, opening_index, side, x, y, z, thickness, depth, height, material)
            group_name = "Na_Casement_#{opening_index}_#{side}_Stile"
            na_create_grouped_box(entities, group_name, x, y, z, thickness, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Casement Rail (Horizontal Member)
        # ------------------------------------------------------------
        def self.na_create_casement_rail(entities, opening_index, position, x, y, z, width, depth, thickness, material)
            group_name = "Na_Casement_#{opening_index}_#{position}_Rail"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, thickness, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Glazing Element Helpers
# -----------------------------------------------------------------------------

        # FUNCTION | Create Glass Pane
        # ------------------------------------------------------------
        def self.na_create_glass_pane(entities, opening_index, x, y, z, width, depth, height, material)
            group_name = "Na_Glass_#{opening_index}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Horizontal Glaze Bar
        # ------------------------------------------------------------
        def self.na_create_glaze_bar_horizontal(entities, opening_index, bar_index, x, y, z, width, depth, height, material)
            group_name = "Na_GlazeBar_#{opening_index}_H#{bar_index}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Vertical Glaze Bar
        # ------------------------------------------------------------
        def self.na_create_glaze_bar_vertical(entities, opening_index, bar_index, x, y, z, width, depth, height, material)
            group_name = "Na_GlazeBar_#{opening_index}_V#{bar_index}"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create One Gothic Arc Half (Filled Ring Segment + PushPull)
        # ------------------------------------------------------------
        # Produces ONE clean solid per arc-half (left or right) using
        # SketchUp's idiomatic workflow:
        #   1. Tessellate the outer arc (radius + bar_width/2) into N edges
        #   2. Walk back along the inner arc (radius - bar_width/2)
        #   3. Close the loop and add_face the whole 2D ring-segment
        #   4. PushPull the face by bar_depth into the wall (+Y)
        # This is dramatically faster than fusing N tiny boxes via outer_shell
        # and produces a true SketchUp solid that fuses reliably with the
        # straight glaze bars in the FuseParts pipeline.
        #
        # Group naming:
        #   Na_GlazeBar_{opening_index}_Arch{arch_index}_L   (left half)
        #   Na_GlazeBar_{opening_index}_Arch{arch_index}_R   (right half)
        # The fuse pipeline's regex was updated to recognise this naming
        # alongside the existing _H<n> / _V<n> straight-bar pattern.
        def self.na_create_glaze_bar_arch_half(entities, opening_index, arch_index, side_label, center_x, center_z, radius_outer, radius_inner, start_angle, end_angle, segments, y_offset, bar_depth, material, clip_bounds = nil)
            return nil if bar_depth <= 0 || radius_inner <= 0 || radius_outer <= radius_inner

            seg_count = [segments.to_i, 8].max

            # Build the boundary in 2D (X-Z plane) first so we can run a
            # cheap Sutherland-Hodgman clip against the glass rectangle
            # BEFORE creating the face. This replaces a per-arch-half
            # solid `intersect` with a glass-area bounding cube, saving
            # ~50-200ms per arch half in SketchUp's boolean engine -- the
            # single biggest win for Live Mode performance.
            outer_2d = (0..seg_count).map do |i|
                t = i.to_f / seg_count
                ang = start_angle + (end_angle - start_angle) * t
                [center_x + radius_outer * Math.cos(ang), center_z + radius_outer * Math.sin(ang)]
            end
            inner_2d = (0..seg_count).to_a.reverse.map do |i|
                t = i.to_f / seg_count
                ang = start_angle + (end_angle - start_angle) * t
                [center_x + radius_inner * Math.cos(ang), center_z + radius_inner * Math.sin(ang)]
            end
            boundary_2d = outer_2d + inner_2d

            if clip_bounds.is_a?(Hash)
                boundary_2d = na_clip_polygon_to_aabb_2d(boundary_2d, clip_bounds)
                return nil if boundary_2d.nil? || boundary_2d.length < 3
            end

            boundary_pts = boundary_2d.map { |xz| Geom::Point3d.new(xz[0], y_offset, xz[1]) }

            group_name = "Na_GlazeBar_#{opening_index}_Arch#{arch_index}_#{side_label}"
            group = entities.add_group
            group.name = group_name

            face = group.entities.add_face(boundary_pts)
            if face.nil?
                group.erase!
                return nil
            end

            # Ensure PushPull extrudes into +Y (wall depth) regardless of
            # which side SketchUp assigned the face normal.
            push_distance = (face.normal.y >= 0) ? bar_depth : -bar_depth
            face.pushpull(push_distance)

            # Paint BOTH sides of every face so the solid renders the same
            # whether SketchUp's view samples the front or the back during
            # later boolean operations. Equal materials on both sides also
            # mean the fuse pipeline does not leave a visible seam where
            # the arch meets the straight glaze bars (the seam shows up
            # only when neighbouring faces disagree on a back material).
            if material
                group.entities.grep(Sketchup::Face).each do |f|
                    f.material      = material
                    f.back_material = material
                end
            end

            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | Sutherland-Hodgman Polygon Clip Against Axis-Aligned Rectangle
        # ------------------------------------------------------------
        # Pure 2D Ruby clipping for the arch boundary points. `points`
        # is an Array of [x, y] pairs (here y is the SketchUp Z axis).
        # `bounds` is a Hash with :x_min, :x_max, :y_min, :y_max keys.
        # Returns a new Array of clipped [x, y] pairs (possibly empty).
        #
        # Used to clip arch ring-segment face boundaries to the glass
        # rectangle BEFORE add_face -- ~1000x faster than running a
        # SketchUp solid Group#intersect on the equivalent 3D extrusion.
        def self.na_clip_polygon_to_aabb_2d(points, bounds)
            return [] if points.nil? || points.empty?
            out = points
            out = na_clip_polygon_against_edge_2d(out, :left,   bounds[:x_min])
            out = na_clip_polygon_against_edge_2d(out, :right,  bounds[:x_max])
            out = na_clip_polygon_against_edge_2d(out, :bottom, bounds[:y_min])
            out = na_clip_polygon_against_edge_2d(out, :top,    bounds[:y_max])
            out
        end
        # ---------------------------------------------------------------

        # FUNCTION | Sutherland-Hodgman Step: Clip Against One Axis-Aligned Edge
        # ------------------------------------------------------------
        def self.na_clip_polygon_against_edge_2d(poly, side, bound)
            return [] if poly.nil? || poly.empty?

            inside = lambda do |pt|
                case side
                when :left   then pt[0] >= bound
                when :right  then pt[0] <= bound
                when :bottom then pt[1] >= bound
                when :top    then pt[1] <= bound
                end
            end

            intersect_pt = lambda do |a, b|
                case side
                when :left, :right
                    dx = b[0] - a[0]
                    t = dx.abs < 1e-12 ? 0.0 : (bound - a[0]).to_f / dx
                    [bound, a[1] + t * (b[1] - a[1])]
                when :bottom, :top
                    dy = b[1] - a[1]
                    t = dy.abs < 1e-12 ? 0.0 : (bound - a[1]).to_f / dy
                    [a[0] + t * (b[0] - a[0]), bound]
                end
            end

            result = []
            prev = poly.last
            prev_in = inside.call(prev)
            poly.each do |curr|
                curr_in = inside.call(curr)
                if curr_in
                    result << intersect_pt.call(prev, curr) unless prev_in
                    result << curr
                elsif prev_in
                    result << intersect_pt.call(prev, curr)
                end
                prev    = curr
                prev_in = curr_in
            end
            result
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cill Element Helper
# -----------------------------------------------------------------------------

        # FUNCTION | Create Cill
        # ------------------------------------------------------------
        def self.na_create_cill(entities, x, y, z, width, depth, height, material)
            group_name = "Na_Cill"
            na_create_grouped_box(entities, group_name, x, y, z, width, depth, height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryHelpers
end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
