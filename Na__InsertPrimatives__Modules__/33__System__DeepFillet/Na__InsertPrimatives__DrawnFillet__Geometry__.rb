# =============================================================================
# NA INSERT PRIMATIVES - DEEP FILLET GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnFillet__Geometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : The fillet profile (a true radius), its automatic side count,
#              and its solve for one edge
# CREATED    : 2026
#
# DESCRIPTION:
# - The fillet's own curve and nothing else. Reading the corner, planning,
#   building and mitring any profile is shared with every profile tool in
#   04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb.
#
# TWO KINDS, ONE RADIUS:
#   round  the fillet proper: an arc of radius r TANGENT to both faces, so
#          the edge rounds over with no line where it meets them. Its centre
#          sits on the bisector r / sin(half) from the corner and it touches
#          each face r / tan(half) back from the edge — r on a square corner.
#   cove   TAB's alternative: an arc of radius r centred ON the edge, cutting
#          a quarter hollow that meets both faces square, r back from it.
#   Both are circles in WORLD space at any corner angle — the section is
#   solved in world space and carried back into the space the edge reports
#   through the inverse of target[:transformation], so a radius is a radius
#   even inside a rotated, nested or non-uniformly scaled component.
#
# SIDES — HOW MANY FACETS MAKE THE ARC:
#   Chosen from the radius unless typed:
#     under R10            6
#     R10 up to R200      12
#     R200 up to R2000    24
#     R2000 and over      48
#   A typed "##s" overrides it for the fillet in hand; see the tool.
#
# CONCAVE EDGES:
# - On an internal corner the same construction fills the corner up to the
#   arc instead of cutting it away: a round becomes the classic internal
#   fillet, a cove a quadrant bead. The shared build faces the facets at the
#   air either way.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__'

module Na__InsertPrimatives

    # @delegate: ../04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb

    # -----------------------------------------------------------------------------
    # REGION | Fillet Constants
    # -----------------------------------------------------------------------------

    # [radius below this in mm, sides]; anything larger takes the last count.
    NA_FILLET_SIDE_BANDS   = [[10.0, 6], [200.0, 12], [2000.0, 24]].freeze
    NA_FILLET_LARGE_SIDES  = 48
    NA_FILLET_MIN_SIDES    = 1                                                # <-- One side is a chamfer, which is still a legal fillet
    NA_FILLET_MAX_SIDES    = 360
    NA_FILLET_MIN_OPENING  = 0.001                                            # <-- Radians; a corner this sharp or this flat has no arc

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Sides
    # -----------------------------------------------------------------------------

    # FUNCTION | How Many Facets a Fillet of This Radius Gets by Default
    # The radius is rounded to a millionth of a millimetre first, so a radius
    # the grid put exactly on a band edge (R10, R200) lands in the band above
    # rather than a hair below it.
    # ------------------------------------------------------------
    def self.Na__DrawnFillet__AutoSides(radius_world)
        radius_mm = (radius_world.to_f.abs * NA_DRAWN_INCH_TO_MM).round(6)

        NA_FILLET_SIDE_BANDS.each do |limit_mm, sides|
            return sides if radius_mm < limit_mm
        end

        NA_FILLET_LARGE_SIDES
    end
    # ---------------------------------------------------------------

    # FUNCTION | Clamp a Typed Side Count Into a Buildable Range
    # ------------------------------------------------------------
    def self.Na__DrawnFillet__ClampSides(value)
        count = value.to_i
        return NA_FILLET_MIN_SIDES if count < NA_FILLET_MIN_SIDES

        count > NA_FILLET_MAX_SIDES ? NA_FILLET_MAX_SIDES : count
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Solve
    # -----------------------------------------------------------------------------

    # FUNCTION | The Fillet Section in the Corner's Own World Plane
    # Returns [[x, y], ...] from face A to face B, where x runs along face A
    # away from the edge and y across to face B's side, for a corner opening
    # (the angle between the faces, radians). The ends are written exactly so
    # they land on the faces.
    # ------------------------------------------------------------
    def self.Na__DrawnFillet__SectionXY(radius, opening, kind, sides)
        r     = radius.to_f
        count = Na__InsertPrimatives.Na__DrawnFillet__ClampSides(sides)
        cos_o = Math.cos(opening)
        sin_o = Math.sin(opening)

        if kind == :cove
            points = (0..count).map do |index|
                angle = opening * index / count
                [r * Math.cos(angle), r * Math.sin(angle)]
            end

            points[0]  = [r, 0.0]
            points[-1] = [r * cos_o, r * sin_o]
            return points
        end

        half     = opening * 0.5
        setback  = r / Math.tan(half)
        centre_d = r / Math.sin(half)
        centre_x = centre_d * Math.cos(half)
        centre_y = centre_d * Math.sin(half)

        start  = Math.atan2(0.0 - centre_y, setback - centre_x)
        finish = Math.atan2((setback * sin_o) - centre_y, (setback * cos_o) - centre_x)
        sweep  = finish - start
        sweep -= 2.0 * Math::PI while sweep > Math::PI                        # <-- The short way round, through the side nearest the corner
        sweep += 2.0 * Math::PI while sweep < -Math::PI

        points = (0..count).map do |index|
            angle = start + (sweep * index / count)
            [centre_x + (r * Math.cos(angle)), centre_y + (r * Math.sin(angle))]
        end

        points[0]  = [setback, 0.0]
        points[-1] = [setback * cos_o, setback * sin_o]
        points
    end
    # ---------------------------------------------------------------

    # FUNCTION | Solve the Fillet for One Edge at a World Radius
    # Returns the shared profile solve (Na__ProfileSweep__SolveHash) plus
    #   :kind          :round or :cove
    #   :symmetric     true — a fillet reads the same from either face, so any
    #                  two meeting at a square corner mitre
    #   :facets        how many facets make the arc
    #   :radius_world  the radius it was solved at
    #   :setback_world how far back from the edge it meets each face
    # nil when the edge cannot carry a fillet.
    # ------------------------------------------------------------
    def self.Na__DrawnFillet__Solve(target, radius_world, kind = :round, sides = 12)
        frame = Na__InsertPrimatives.Na__ProfileSweep__CornerFrame(target)
        return nil unless frame

        radius = radius_world.to_f
        return nil unless radius > 0.0

        xform    = target[:transformation]
        world_v0 = frame[:v0].transform(xform)
        world_v1 = frame[:v1].transform(xform)
        heading  = world_v1 - world_v0
        return nil if heading.length == 0
        heading.normalize!

        # Each face's direction away from the edge, square to it in WORLD
        # space: the local direction carried out, with any lean along the
        # edge that a non-uniform scale introduced taken back off.
        across = lambda do |direction|
            vector = direction.transform(xform)
            along  = vector.dot(heading).to_f
            square = Geom::Vector3d.new(
                vector.x.to_f - (heading.x.to_f * along),
                vector.y.to_f - (heading.y.to_f * along),
                vector.z.to_f - (heading.z.to_f * along)
            )
            square.length > 0 ? square.normalize : nil
        end

        axis_x  = across.call(frame[:dir_a])
        towards = across.call(frame[:dir_b])
        return nil unless axis_x && towards

        cos_open = [[axis_x.dot(towards).to_f, 1.0].min, -1.0].max
        opening  = Math.acos(cos_open)
        return nil unless opening > NA_FILLET_MIN_OPENING && opening < Math::PI - NA_FILLET_MIN_OPENING

        axis_y = Geom::Vector3d.new(
            towards.x.to_f - (axis_x.x.to_f * cos_open),
            towards.y.to_f - (axis_x.y.to_f * cos_open),
            towards.z.to_f - (axis_x.z.to_f * cos_open)
        )
        return nil unless axis_y.length > 0
        axis_y.normalize!

        section = Na__InsertPrimatives.Na__DrawnFillet__SectionXY(radius, opening, kind, sides)
        inverse = xform.inverse

        lay = lambda do |corner|
            section.map do |x, y|
                Geom::Point3d.new(
                    corner.x.to_f + (axis_x.x.to_f * x) + (axis_y.x.to_f * y),
                    corner.y.to_f + (axis_x.y.to_f * x) + (axis_y.y.to_f * y),
                    corner.z.to_f + (axis_x.z.to_f * x) + (axis_y.z.to_f * y)
                )
            end
        end

        world0 = lay.call(world_v0)
        world1 = lay.call(world_v1)

        Na__InsertPrimatives.Na__ProfileSweep__SolveHash(
            frame, target,
            world0.map { |point| point.transform(inverse) },
            world1.map { |point| point.transform(inverse) },
            {
                :kind          => kind,
                :symmetric     => true,
                :facets        => section.length - 1,
                :radius_world  => radius,
                :size_world    => radius,
                :setback_world => kind == :cove ? radius : radius / Math.tan(opening * 0.5)
            },
            world0, world1
        )
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP FILLET GEOMETRY
# =============================================================================
