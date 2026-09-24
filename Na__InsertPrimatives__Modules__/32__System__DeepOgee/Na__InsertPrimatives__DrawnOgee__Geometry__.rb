# =============================================================================
# NA INSERT PRIMATIVES - DEEP OGEE GEOMETRY
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnOgee__Geometry__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : The ogee profile and its solve for one edge
# CREATED    : 2026
#
# DESCRIPTION:
# - The ogee's own curve and nothing else. Reading the corner, planning,
#   building and mitring any profile is shared with every profile tool in
#   04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb.
#
# THE PROFILE — A ROMAN OGEE, TWO QUARTER ARCS:
#   In the corner's own frame (u runs along the ROLL face into the material,
#   w along the STEP face), for a size s:
#     roll  a convex quarter arc, radius s/2, centred (s, s/2), leaving the
#           roll face TANGENT, so the edge rolls over like a bullnose
#     cove  a concave quarter arc, radius s/2, centred (0, s/2), arriving at
#           the step face square: the crisp lip under the cove
#   The two arcs meet tangent at (s/2, s/2), the inflection of the S. A square
#   corner gives a true circular ogee. Any other corner angle gives the same
#   shape in the oblique frame of its two faces, so the roll still leaves its
#   face tangent and the lip still runs parallel to it.
#
# WHICH FACE ROLLS:
# - The face lying nearer horizontal (larger |Z| of its world normal), so the
#   top and the underside of a table top both roll over, and every edge in a
#   banked batch agrees about it, which is what lets two of them mitre. TAB
#   flips it for all of them at once. A tie (a vertical corner, both faces
#   upright) goes to the edge's first face.
#
# FACETS:
# - Each quarter arc gets a quarter of the plugin's Circle Sides setting
#   (24 -> 6 per arc, 12 facets), so "48s" smooths an ogee exactly as it
#   smooths a cylinder. Never fewer than two per arc.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__'

module Na__InsertPrimatives

    # @delegate: ../04__GeometryHelpers/Na__InsertPrimatives__DrawnProfileSweep__.rb

    # -----------------------------------------------------------------------------
    # REGION | Ogee Constants
    # -----------------------------------------------------------------------------

    NA_OGEE_MIN_ARC_SEGMENTS     = 2                                          # <-- Facets per quarter arc, at the least
    NA_OGEE_DEFAULT_ARC_SEGMENTS = 6                                          # <-- A quarter of the 24-sided circle default
    NA_OGEE_LEVEL_TIE            = 0.001                                      # <-- Two faces this close in level are a tie

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Profile
    # -----------------------------------------------------------------------------

    # FUNCTION | The Ogee Profile in the Corner's Own Frame
    # Returns [[u, w], ...] from the roll face (s, 0) to the step face (0, s),
    # in whatever units size is given in: the roll arc, then the cove arc,
    # sharing the inflection point once. The three key points are written
    # exactly rather than left to trigonometry, so the ends land precisely on
    # the faces and the rebuilt faces knit onto them.
    # ------------------------------------------------------------
    def self.Na__DrawnOgee__ProfileUW(size, arc_segments)
        s      = size.to_f
        r      = s * 0.5
        count  = [arc_segments.to_i, NA_OGEE_MIN_ARC_SEGMENTS].max
        points = []

        # Roll: centre (s, s/2), from -90 degrees (on the roll face) to -180.
        (0..count).each do |index|
            angle = (-90.0 - (90.0 * index / count)) * Math::PI / 180.0
            points << [s + (r * Math.cos(angle)), r + (r * Math.sin(angle))]
        end

        # Cove: centre (0, s/2), from 0 degrees (the inflection) to 90.
        (1..count).each do |index|
            angle = (90.0 * index / count) * Math::PI / 180.0
            points << [r * Math.cos(angle), r + (r * Math.sin(angle))]
        end

        points[0]     = [s, 0.0]
        points[count] = [r, r]
        points[-1]    = [0.0, s]
        points
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Roll Sit on Face A, Before Any TAB Flip?
    # The face nearer horizontal rolls — see the header. Normals are read in
    # world space, so a rotated or nested group answers the way it is seen.
    # ------------------------------------------------------------
    def self.Na__DrawnOgee__RollOnA?(face_a, face_b, xform)
        level = lambda do |face|
            normal = face.normal.transform(xform)
            normal.length > 0 ? (normal.z.to_f / normal.length.to_f).abs : 0.0
        end

        level.call(face_a) + NA_OGEE_LEVEL_TIE >= level.call(face_b)
    rescue StandardError
        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Solve
    # -----------------------------------------------------------------------------

    # FUNCTION | Solve the Ogee for One Edge at a World Size
    # Returns the shared profile solve (Na__ProfileSweep__SolveHash) plus
    #   :roll_on_a   which face the roll leaves (after any flip); an ogee is
    #                not symmetric, so a mitre needs both edges to agree on it
    #   :facets      how many facets the profile has
    #   :size_world  the size it was solved at
    # nil when the edge cannot carry a moulding — the chamfer's refusals.
    #
    # The world size becomes a separate LOCAL distance along each face
    # direction, from the instance scale that way, so the moulding keeps its
    # proportions in world space inside a non-uniformly scaled component.
    # ------------------------------------------------------------
    def self.Na__DrawnOgee__Solve(target, offset_world, flip = false, arc_segments = NA_OGEE_DEFAULT_ARC_SEGMENTS)
        frame = Na__InsertPrimatives.Na__ProfileSweep__CornerFrame(target)
        return nil unless frame

        size = offset_world.to_f
        return nil unless size > 0.0

        face_a, face_b = target[:faces]
        roll_on_a = Na__InsertPrimatives.Na__DrawnOgee__RollOnA?(face_a, face_b, target[:transformation])
        roll_on_a = !roll_on_a if flip

        roll_dir, roll_scale, step_dir, step_scale =
            if roll_on_a
                [frame[:dir_a], frame[:scale_a], frame[:dir_b], frame[:scale_b]]
            else
                [frame[:dir_b], frame[:scale_b], frame[:dir_a], frame[:scale_a]]
            end

        profile_uw = Na__InsertPrimatives.Na__DrawnOgee__ProfileUW(size, arc_segments)

        # The profile runs roll -> step; it is stored a -> b like every other
        # point pair in the chamfer family, so a face-B roll is laid reversed.
        lay = lambda do |corner|
            points = profile_uw.map do |u, w|
                along = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(corner, roll_dir, u / roll_scale)
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(along, step_dir, w / step_scale)
            end

            roll_on_a ? points : points.reverse
        end

        Na__InsertPrimatives.Na__ProfileSweep__SolveHash(
            frame, target, lay.call(frame[:v0]), lay.call(frame[:v1]),
            {
                :roll_on_a  => roll_on_a,
                :symmetric  => false,
                :facets     => profile_uw.length - 1,
                :size_world => size
            }
        )
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP OGEE GEOMETRY
# =============================================================================
