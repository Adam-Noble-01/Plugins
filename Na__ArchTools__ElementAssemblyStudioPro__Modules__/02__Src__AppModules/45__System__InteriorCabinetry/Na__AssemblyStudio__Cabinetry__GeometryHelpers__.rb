# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - GEOMETRY HELPERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__GeometryHelpers__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__GeometryHelpers
# AUTHOR     : Noble Architecture
# PURPOSE    : The few primitives every cabinetry builder shares: mm points,
#              a box from a layout part, faces added with a known outward side,
#              and closed prisms (a planar profile run along an axis).
# CREATED    : 29-Oct-2026
#
# DESCRIPTION:
# - Every builder works in the cabinet's ComponentDefinition, a closed
#   context, so all coordinates here are the definition's own (local) and no
#   active-context conversion is ever applied (see the Coordinate Rule).
# - Faces are added from explicit points and then turned so they face the
#   side the caller names. Nothing relies on add_face winding or pushpull
#   direction, which differ between contexts and SketchUp versions.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Units__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__GeometryHelpers

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        Box        = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box
        Units      = Na__AssemblyStudio::Na__GeometryHelpers::Na__Units

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Units and Points
# -----------------------------------------------------------------------------

        # FUNCTION | Millimetres to SketchUp Inches
        # ------------------------------------------------------------
        def self.na_mm(value_mm)
            Units.na_mm_to_inch(value_mm)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Point From Millimetre Coordinates
        # ------------------------------------------------------------
        def self.na_point(x_mm, y_mm, z_mm)
            Geom::Point3d.new(na_mm(x_mm), na_mm(y_mm), na_mm(z_mm))
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Groups and Boxes
# -----------------------------------------------------------------------------

        # FUNCTION | Add a Named Group
        # ------------------------------------------------------------
        def self.na_add_group(entities, name)
            group      = entities.add_group
            group.name = name
            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build One Layout Box Part as a Named Grouped Box
        # ------------------------------------------------------------
        # @param part [Hash] { :name, :x0, :x1, :y0, :y1, :z0, :z1 } in mm
        # @return [Sketchup::Group, nil]
        def self.na_add_box_part(entities, part, prefix, material)
            Box.na_create_grouped_box(
                entities, "#{prefix}#{part[:name]}",
                na_mm(part[:x0]), na_mm(part[:y0]), na_mm(part[:z0]),
                na_mm(part[:x1] - part[:x0]), na_mm(part[:y1] - part[:y0]), na_mm(part[:z1] - part[:z0]),
                material
            )
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Faces With a Known Outward Side
# -----------------------------------------------------------------------------

        # FUNCTION | Add a Face and Turn It to Face a Given Direction
        # ------------------------------------------------------------
        # @param points  [Array<Geom::Point3d>]
        # @param outward [Geom::Vector3d] the side the front of the face shows
        # @return [Sketchup::Face, nil]
        def self.na_add_oriented_face(entities, points, outward, material = nil)
            face = entities.add_face(points)
            return nil unless face && face.valid?
            face.reverse! if face.normal.dot(outward) < 0
            if material
                face.material      = material
                face.back_material = material
            end
            face
        rescue ArgumentError => e
            DebugTools.na_debug_warn("Cabinetry face skipped: #{e.message}")
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Soften the Edge Joining Two Points, If One Exists
        # ------------------------------------------------------------
        def self.na_soften_edge_between(entities, point_a, point_b)
            entities.grep(Sketchup::Edge).each do |edge|
                a = edge.start.position
                b = edge.end.position
                next unless (a == point_a && b == point_b) || (a == point_b && b == point_a)
                edge.soft   = true
                edge.smooth = true
                return true
            end
            false
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Prisms (a Planar Profile Run Along an Axis)
# -----------------------------------------------------------------------------

        # FUNCTION | Build a Closed Prism From a 2D Profile
        # ------------------------------------------------------------
        # The profile is a closed polygon in its own (a, b) frame, in mm.
        # Point (a, b, w) maps to origin + a*axis_a + b*axis_b + w*axis_w,
        # with w running 0..length along axis_w. Either winding is accepted:
        # each side face is turned to face away from the profile's inside.
        #
        # @param entities    [Sketchup::Entities] (usually a new group's)
        # @param profile     [Array<Array(Float, Float)>] (a, b) in mm
        # @param origin      [Array(Float, Float, Float)] mm
        # @param axis_a      [Array(Float, Float, Float)] unit vector
        # @param axis_b      [Array(Float, Float, Float)] unit vector
        # @param axis_w      [Array(Float, Float, Float)] unit vector
        # @param length      [Float] mm along axis_w
        # @param soft_points [Array<Integer>] profile indices whose run edge
        #                     is softened (facets of an arc)
        # @return [Integer] faces added
        def self.na_add_prism(entities, profile, origin, axis_a, axis_b, axis_w, length, material = nil, soft_points = [])
            pts = na_dedupe_profile(profile)
            return 0 if pts.length < 3

            to_point = lambda do |a, b, w|
                na_point(origin[0] + a * axis_a[0] + b * axis_b[0] + w * axis_w[0],
                         origin[1] + a * axis_a[1] + b * axis_b[1] + w * axis_w[1],
                         origin[2] + a * axis_a[2] + b * axis_b[2] + w * axis_w[2])
            end
            vector = lambda { |x, y, z| Geom::Vector3d.new(x, y, z) }
            sign   = na_signed_area(pts) >= 0 ? 1.0 : -1.0
            faces  = 0

            start_pts = pts.map { |a, b| to_point.call(a, b, 0.0) }
            end_pts   = pts.map { |a, b| to_point.call(a, b, length) }
            faces += 1 if na_add_oriented_face(entities, start_pts, vector.call(*axis_w.map { |c| -c }), material)
            faces += 1 if na_add_oriented_face(entities, end_pts,   vector.call(*axis_w), material)

            pts.each_with_index do |(a0, b0), index|
                a1, b1 = pts[(index + 1) % pts.length]
                da = a1 - a0
                db = b1 - b0
                out_a =  db * sign                                           # <-- In-plane outward normal of this segment
                out_b = -da * sign
                outward = vector.call(out_a * axis_a[0] + out_b * axis_b[0],
                                      out_a * axis_a[1] + out_b * axis_b[1],
                                      out_a * axis_a[2] + out_b * axis_b[2])
                quad = [to_point.call(a0, b0, 0.0), to_point.call(a1, b1, 0.0),
                        to_point.call(a1, b1, length), to_point.call(a0, b0, length)]
                faces += 1 if na_add_oriented_face(entities, quad, outward, material)
            end

            soft_points.each do |index|
                next unless index >= 0 && index < pts.length
                a, b = pts[index]
                na_soften_edge_between(entities, to_point.call(a, b, 0.0), to_point.call(a, b, length))
            end
            faces
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Drop Repeated Consecutive Profile Points
        # ------------------------------------------------------------
        def self.na_dedupe_profile(profile)
            out = []
            profile.each do |point|
                out << point unless out.last && (out.last[0] - point[0]).abs < 1e-6 && (out.last[1] - point[1]).abs < 1e-6
            end
            out.pop if out.length > 1 && (out.first[0] - out.last[0]).abs < 1e-6 && (out.first[1] - out.last[1]).abs < 1e-6
            out
        end
        private_class_method :na_dedupe_profile
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Signed Area of a Closed 2D Polygon (Shoelace)
        # ------------------------------------------------------------
        def self.na_signed_area(points)
            sum = 0.0
            points.each_with_index do |(a0, b0), index|
                a1, b1 = points[(index + 1) % points.length]
                sum += a0 * b1 - a1 * b0
            end
            sum / 2.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Points Round a Circle (a, b), Counter-Clockwise
        # ------------------------------------------------------------
        def self.na_circle_profile(radius, segments)
            (0...segments).map do |index|
                angle = 2.0 * Math::PI * index / segments
                [radius * Math.cos(angle), radius * Math.sin(angle)]
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryHelpers
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
