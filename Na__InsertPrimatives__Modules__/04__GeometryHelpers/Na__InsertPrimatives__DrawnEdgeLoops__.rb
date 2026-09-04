# =============================================================================
# NA INSERT PRIMATIVES - INSET EDGE LOOPS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnEdgeLoops__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Turn an INWARD quad-mode drag into an inset edge loop cut instead
#              of a shortening push
# CREATED    : 2026
#
# DESCRIPTION:
# - QUAD mode already puts a line back where an OUTWARD push started, so two
#   runs of wall meet on a real corner. Dragged the other way it did nothing at
#   all: the start loop ends up outside the now-shorter solid, bounds no face,
#   and the ring self-cleans straight back off. The gesture was dead.
# - So inward is given its own meaning. With quads armed, dragging a face INTO
#   the material no longer shortens anything — it cuts an edge loop across the
#   faces around it, inset from the original face by the drag distance. That is
#   the loop-cut half of the tool: mark a 450mm nib, a pier, a return, without
#   drawing a single line by hand.
#
# WHY THE OFFSET RING LANDS ON REAL FACES:
# - The faces around a pushed face are the SWEEP of its loop along its normal.
#   So a start-loop edge, offset along that same normal, lies exactly IN the
#   face it generated — not near it, in it. Handing those points to add_edges
#   splits each surrounding face in two, which is an edge loop.
# - This is the identical mechanism QUAD mode uses outward, aimed at a different
#   plane. It is deliberately not a second copy of that code:
#   Na__PushPull__StitchQuadRing already carries the landing check, the fill
#   face removal and the self-clean, all of which apply here unchanged.
#
# WHAT MAKES IT SAFE ON GEOMETRY THAT IS NOT A CLEAN PRISM:
# - A chamfered or non-planar surround is not the sweep of the loop, so the
#   offset edges land in mid-air inside the solid. Bounding no face, they are
#   swept back off by the same self-clean that handles everything else. Worst
#   case the gesture does nothing and says so in the console — it never leaves a
#   stray ring behind, and it never removes anything that was already there.
#
# THE SOLID IS NEVER PUSHED:
# - No pushpull runs on this path at all. That is the whole point: an inward
#   drag with quads on is a cut, not a shortening. Quads OFF still shortens, so
#   TAB is the switch between the two and neither behaviour is lost.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__QuadRing__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Edge Loop Constants
    # -----------------------------------------------------------------------------

    # Inches. Below this there is no daylight between the cut and the face it is
    # measured from, and add_edges would be asked to land a ring on top of an
    # existing one.
    NA_EDGE_LOOP_MIN_TRAVEL = 0.0040                                          # <-- ~0.1mm

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Direction Test
    # -----------------------------------------------------------------------------

    # FUNCTION | Is This Drag a Loop Cut Rather Than a Push?
    # ------------------------------------------------------------
    # The one rule, in one place so the preview and the commit can never
    # disagree about which of the two a given drag is going to be.
    #
    # The travel is the SIGNED distance along the face normal, not the raw drag:
    # an axis lock divides by the cosine between the axis and the normal, and
    # that cosine can be negative — so a drag the mouse says is positive can be
    # travelling into the material. Asking the travel is asking the geometry.
    # ------------------------------------------------------------
    def self.Na__EdgeLoops__IsCut?(quad_mode, normal_travel)
        return false unless quad_mode

        normal_travel.to_f < 0.0
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Loop Offsetting
    # -----------------------------------------------------------------------------

    # FUNCTION | Move Captured Loops Along a Normal
    # ------------------------------------------------------------
    # Everything here is DEFINITION-LOCAL: the loops come from
    # Na__PushPull__CaptureLoops, the normal is the face's own, and the distance
    # is the local one pushpull would have been given. Mixing in a world value
    # would offset by the instance scale as well as the distance.
    # ------------------------------------------------------------
    def self.Na__EdgeLoops__OffsetLoops(loops_local, normal_local, distance_local)
        return [] unless loops_local && normal_local

        travel = distance_local.to_f
        offset = Geom::Vector3d.new(
            normal_local.x.to_f * travel,
            normal_local.y.to_f * travel,
            normal_local.z.to_f * travel
        )

        loops_local.map do |points|
            next nil if points.nil? || points.length < 3

            points.map { |point| point.offset(offset) }
        end.compact
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Cut
    # -----------------------------------------------------------------------------

    # FUNCTION | Cut Inset Edge Loops Into the Faces Around a Face
    # ------------------------------------------------------------
    # Returns the same stats shape the quad ring returns — { :kept, :swept,
    # :faces_removed, :misplaced } plus :loops — so the console report and the
    # "ring landed in the wrong space" warning need no second code path.
    #
    # Reads: kept edges are the loop cut that survived; swept ones were aimed at
    # a surround that is not the sweep of the loop and bounded nothing.
    # ------------------------------------------------------------
    def self.Na__EdgeLoops__Cut(entities, loops_local, normal_local, distance_local, build_transform)
        stats = { :kept => 0, :swept => 0, :faces_removed => 0, :misplaced => false, :loops => 0 }
        return stats unless entities && loops_local && normal_local
        return stats if distance_local.to_f.abs < NA_EDGE_LOOP_MIN_TRAVEL

        inset = Na__InsertPrimatives.Na__EdgeLoops__OffsetLoops(loops_local, normal_local, distance_local)
        return stats if inset.empty?

        result = Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, inset, build_transform)

        stats[:kept]          = result[:kept].to_i
        stats[:swept]         = result[:swept].to_i
        stats[:faces_removed] = result[:faces_removed].to_i
        stats[:misplaced]     = result[:misplaced] ? true : false
        stats[:loops]         = inset.length
        stats
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Line Saying What the Loop Cut Actually Did
    # ------------------------------------------------------------
    def self.Na__EdgeLoops__Report(stats)
        return 'none' unless stats

        summary = "#{stats[:loops]} loop(s) — #{stats[:kept]} edges kept, " \
                  "#{stats[:swept]} swept, #{stats[:faces_removed]} fill face(s) removed"
        summary << ' — RING LANDED IN THE WRONG SPACE, removed' if stats[:misplaced]
        summary << ' — the surround is not a clean sweep of this face' if stats[:kept].to_i.zero?
        summary
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF INSET EDGE LOOPS MODULE
# =============================================================================
