# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - FRONT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__FrontBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__FrontBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds every door and drawer front of a resolved layout in one
#              of the three styles: Flat, Shaker or Recessed Handle.
# CREATED    : 29-Oct-2026
#
# THE THREE STYLES
# - Flat     : a plain slab.
# - Shaker   : a frame of two stiles and two rails round a recessed centre
#              panel. The stiles and rails are separate faces on the front,
#              so the frame joints read as on a real shaker door; the panel
#              sits the recess depth back, with four reveal faces round it.
# - Recessed : a slab with a round-bottomed finger groove routed across it a
#              set distance in from the opening edge (top of base fronts,
#              bottom of wall doors, up the opening edge of a full height
#              tall door). Built as the grooved side profile run the width of
#              the front, so the groove is real geometry, not a texture.
#
# DESCRIPTION:
# - Each front is its own solid group, named Na__Front__<part>, inside
#   Na__Cabinet__Fronts. Faces are added from explicit points and turned to
#   face outward (Na__GeometryHelpers), so no pushpull is used.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__Cabinetry__GeometryHelpers__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__FrontBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__GeometryHelpers

        NA_GROUP_NAME      = "Na__Cabinet__Fronts".freeze
        NA_PART_PREFIX     = "Na__Front__".freeze
        NA_GROOVE_SEGMENTS = 12                                                # <-- Facets round the groove's half-round bottom

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Fronts Group (Nil When the Unit Is Open)
        # ------------------------------------------------------------
        # @return [Sketchup::Group, nil]
        def self.na_build(layout, entities, materials)
            return nil if layout[:fronts].empty?
            group = GeometryHelpers.na_add_group(entities, NA_GROUP_NAME)
            layout[:fronts].each { |front| na_build_front(front, group.entities, materials[:door]) }
            DebugTools.na_debug_geometry("Cabinet fronts: #{layout[:fronts].length} (#{layout[:fronts].first[:style]})")
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | One Front
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Build One Front in Its Style
        # ------------------------------------------------------------
        def self.na_build_front(front, entities, material)
            name = "#{NA_PART_PREFIX}#{front[:name]}"
            if front[:shaker]
                group = GeometryHelpers.na_add_group(entities, name)
                na_build_shaker(front, group.entities, material)
                group
            elsif front[:groove]
                group = GeometryHelpers.na_add_group(entities, name)
                na_build_grooved(front, group.entities, material)
                group
            else
                GeometryHelpers.na_add_box_part(entities, front, NA_PART_PREFIX, material)
            end
        end
        private_class_method :na_build_front
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shaker
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Frame, Reveals and Recessed Panel (Fourteen Faces)
        # ------------------------------------------------------------
        # yf is the front face (most negative Y), yb the back face. The panel
        # sits at yp = yf + recess.
        def self.na_build_shaker(front, entities, material)
            x0, x1, z0, z1 = front[:x0], front[:x1], front[:z0], front[:z1]
            yf, yb = front[:y0], front[:y1]
            s  = front[:shaker][:stile]
            r  = front[:shaker][:rail]
            yp = yf + front[:shaker][:recess]
            xi0, xi1, zi0, zi1 = x0 + s, x1 - s, z0 + r, z1 - r
            p  = ->(x, y, z) { GeometryHelpers.na_point(x, y, z) }
            v  = ->(x, y, z) { Geom::Vector3d.new(x, y, z) }
            add = ->(pts, out) { GeometryHelpers.na_add_oriented_face(entities, pts, out, material) }

            add.call([p.(x0, yb, z0), p.(x1, yb, z0), p.(x1, yb, z1), p.(x0, yb, z1)], v.(0, 1, 0))    # <-- Back
            add.call([p.(x0, yf, z0), p.(x0, yb, z0), p.(x0, yb, z1), p.(x0, yf, z1)], v.(-1, 0, 0))   # <-- Left edge
            add.call([p.(x1, yf, z0), p.(x1, yb, z0), p.(x1, yb, z1), p.(x1, yf, z1)], v.(1, 0, 0))    # <-- Right edge
            add.call([p.(x0, yf, z0), p.(x1, yf, z0), p.(x1, yb, z0), p.(x0, yb, z0)], v.(0, 0, -1))   # <-- Bottom edge
            add.call([p.(x0, yf, z1), p.(x1, yf, z1), p.(x1, yb, z1), p.(x0, yb, z1)], v.(0, 0, 1))    # <-- Top edge

            add.call([p.(x0, yf, z0), p.(xi0, yf, z0), p.(xi0, yf, z1), p.(x0, yf, z1)], v.(0, -1, 0))  # <-- Left stile
            add.call([p.(xi1, yf, z0), p.(x1, yf, z0), p.(x1, yf, z1), p.(xi1, yf, z1)], v.(0, -1, 0))  # <-- Right stile
            add.call([p.(xi0, yf, z0), p.(xi1, yf, z0), p.(xi1, yf, zi0), p.(xi0, yf, zi0)], v.(0, -1, 0)) # <-- Bottom rail
            add.call([p.(xi0, yf, zi1), p.(xi1, yf, zi1), p.(xi1, yf, z1), p.(xi0, yf, z1)], v.(0, -1, 0)) # <-- Top rail

            add.call([p.(xi0, yf, zi0), p.(xi0, yp, zi0), p.(xi0, yp, zi1), p.(xi0, yf, zi1)], v.(1, 0, 0))   # <-- Reveal, left
            add.call([p.(xi1, yf, zi0), p.(xi1, yp, zi0), p.(xi1, yp, zi1), p.(xi1, yf, zi1)], v.(-1, 0, 0))  # <-- Reveal, right
            add.call([p.(xi0, yf, zi0), p.(xi1, yf, zi0), p.(xi1, yp, zi0), p.(xi0, yp, zi0)], v.(0, 0, 1))   # <-- Reveal, bottom
            add.call([p.(xi0, yf, zi1), p.(xi1, yf, zi1), p.(xi1, yp, zi1), p.(xi0, yp, zi1)], v.(0, 0, -1))  # <-- Reveal, top
            add.call([p.(xi0, yp, zi0), p.(xi1, yp, zi0), p.(xi1, yp, zi1), p.(xi0, yp, zi1)], v.(0, -1, 0))  # <-- Panel
        end
        private_class_method :na_build_shaker
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Recessed Handle (Finger Groove)
# -----------------------------------------------------------------------------

        # SUB FUNCTION | The Grooved Profile, Run Across the Front
        # ------------------------------------------------------------
        # A top or bottom groove runs along X: the profile is drawn in the
        # (Y, Z) plane at x0 and run the front's width. A left or right
        # groove runs up the front: the profile is drawn in the (Y, X) plane
        # at z0 and run its height.
        def self.na_build_grooved(front, entities, material)
            groove     = front[:groove]
            horizontal = (groove[:edge] == "top" || groove[:edge] == "bottom")
            low, high  = horizontal ? [front[:z0], front[:z1]] : [front[:x0], front[:x1]]
            from_high  = (groove[:edge] == "top" || groove[:edge] == "right")
            profile, soft = na_groove_profile(front[:y0], front[:y1], low, high, groove, from_high)

            if horizontal
                GeometryHelpers.na_add_prism(entities, profile, [front[:x0], 0, 0], [0, 1, 0], [0, 0, 1], [1, 0, 0],
                                             front[:x1] - front[:x0], material, soft)
            else
                GeometryHelpers.na_add_prism(entities, profile, [0, 0, front[:z0]], [0, 1, 0], [1, 0, 0], [0, 0, 1],
                                             front[:z1] - front[:z0], material, soft)
            end
        end
        private_class_method :na_build_grooved
        # ---------------------------------------------------------------

        # FUNCTION | The Closed Side Profile of a Grooved Front (Pure, mm)
        # ------------------------------------------------------------
        # (a, b) = (Y, across): the front face at a = yf, the back at a = yb.
        # The groove opens on the front face, `offset` in from the edge
        # (`from_high` measures down from `high`, else up from `low`), is
        # `width` wide and `depth` deep, with a half-round bottom of radius
        # width / 2. Returns [points, indices of the edges to soften]. No
        # point repeats, so the indices stay true after the prism builder
        # tidies the profile.
        def self.na_groove_profile(yf, yb, low, high, groove, from_high)
            radius = groove[:width] / 2.0
            centre = from_high ? high - groove[:offset] - radius : low + groove[:offset] + radius
            deep   = yf + groove[:depth] - radius                                # <-- Centre of the half round
            walls  = deep > yf + 1e-6                                            # <-- Straight sides before the half round

            points = [[yf, low], [yb, low], [yb, high], [yf, high], [yf, centre + radius]]
            soft   = []
            if walls
                soft << points.length                                            # <-- Wall meets the round bottom tangentially
                points << [deep, centre + radius]
            end
            (1...NA_GROOVE_SEGMENTS).each do |index|
                angle = Math::PI / 2.0 - Math::PI * index / NA_GROOVE_SEGMENTS   # <-- From +90 deg (towards high) round to -90
                soft << points.length
                points << [deep + radius * Math.cos(angle), centre + radius * Math.sin(angle)]
            end
            if walls
                soft << points.length
                points << [deep, centre - radius]
            end
            points << [yf, centre - radius]
            [points, soft]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FrontBuilder
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
