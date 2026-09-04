# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL QUAD RING
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__QuadRing__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Put the start-loop edges back after a push so wall corners stay quads
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Quad Ring — Putting the Start Loop Back
    # -----------------------------------------------------------------------------
    #
    # WHAT SKETCHUP DOES AND WHY THE LINE VANISHES:
    # - Pushing a box face outward builds a fresh wall from the start loop to the
    #   finish loop, then MERGES that wall into the coplanar wall it grew out of
    #   and deletes the edge they met on. That deleted edge is the "quad line".
    #   It is not hidden or softened, it is gone, and there is no pushpull flag
    #   that keeps it.
    # - So it is put back: the start loop is re-drawn as edges after the push.
    #   Landing an edge on an existing face splits it — the same merge machinery
    #   that removed the line, run the other way.
    #
    # WHY NOT pushpull(distance, true):
    # - The copy flag ("new starting face") leaves a FACE in the start plane, not
    #   just its edges, and which of the two faces survives flips with the push
    #   direction. Erasing the wrong one opens a hole in the solid. Re-drawing
    #   the loop is direction-agnostic and never removes anything that was there.
    #
    # SELF-CLEANING, BECAUSE THE RING IS NOT ALWAYS WANTED:
    # - Pushing INTO a solid shortens it, so the start loop is left in mid-air.
    #   Rather than special-case the direction, every ring edge that ends up
    #   bounding no face at all is swept back off, which also covers a face that
    #   refused to split. Worst case the push behaves exactly as it does with
    #   quads off — it never leaves debris.
    #
    # -----------------------------------------------------------------------------

    NA_PP_QUAD_TOL = 0.002                                                    # <-- Inches; twice SketchUp's own merge tolerance

    # FUNCTION | Every Loop of a Face, in Definition-Local Points
    # ------------------------------------------------------------
    # Read BEFORE the push: the face is about to move, and these positions are
    # the only record of where it started.
    #
    # CLONED, AND THAT IS THE WHOLE POINT OF THIS FUNCTION:
    # - A record of where something WAS is worthless if it tracks where the
    #   thing goes. Vertex#position must be copied out, not held.
    # - Plain pushpull hid the need for it. It leaves the original vertices
    #   where they are and re-bounds the face on new ones, so a held position
    #   never moved and the ring landed correctly by luck rather than by design.
    # - Slope mode's stretch route moves the face's OWN vertices — that is what
    #   makes it seamless — so a held position followed them. The ring was then
    #   re-drawn on top of the face's new boundary, where add_edges quietly
    #   returned the edges that were already there: four edges "kept", nothing
    #   created, and no line at the joint. That is the quad line that previewed
    #   and never materialised.
    # ------------------------------------------------------------
    def self.Na__PushPull__CaptureLoops(face)
        return [] unless face && face.valid?

        face.loops.map do |loop|
            loop.vertices.map { |vertex| vertex.position.clone }
        end
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Re-Draw the Start Loops as Edges After a Push
    # Returns { :kept, :swept, :faces_removed, :misplaced }.
    # ------------------------------------------------------------
    def self.Na__PushPull__StitchQuadRing(entities, loops_local, build_transform)
        stats = { :kept => 0, :swept => 0, :faces_removed => 0, :misplaced => false }
        return stats unless entities && loops_local

        loops_local.each do |points|
            next if points.nil? || points.length < 3

            ring  = points.map { |point| point.transform(build_transform) }
            ring << ring.first                                                # <-- add_edges runs a polyline, it does not close it

            edges = entities.add_edges(ring)
            next if edges.nil? || edges.empty?

            # If the points landed in the wrong coordinate space the edges are
            # real but useless. Take them straight back out and let the plain
            # push stand rather than leaving a stray loop in the model.
            unless Na__InsertPrimatives.Na__PushPull__RingLanded?(edges, points)
                stats[:misplaced] = true
                edges.each { |edge| edge.erase! if edge.valid? }
                next
            end

            stats[:faces_removed] += Na__InsertPrimatives.Na__PushPull__EraseRingFaces(edges, points)

            edges.each do |edge|
                next unless edge.valid?

                if edge.faces.empty?
                    edge.erase!
                    stats[:swept] += 1
                else
                    stats[:kept] += 1
                end
            end
        end

        stats
    end
    # ---------------------------------------------------------------

    # FUNCTION | Did the Ring Land Where It Was Aimed?
    # Vertex positions read back are always definition-local, so they are checked
    # against the local points, never against the transformed ones.
    # ------------------------------------------------------------
    def self.Na__PushPull__RingLanded?(edges, points_local)
        return false if points_local.nil? || points_local.empty?

        # Every start point must show up as an endpoint. More edges than points
        # is normal and fine — a ring segment that runs through an existing
        # vertex comes back split — but a MISSING corner means the ring is not
        # where it was aimed.
        points_local.all? do |wanted|
            edges.any? do |edge|
                edge.valid? &&
                    (edge.start.position.distance(wanted) < NA_PP_QUAD_TOL ||
                     edge.end.position.distance(wanted)   < NA_PP_QUAD_TOL)
            end
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remove the Face a Closed Ring Just Created
    # A closed coplanar loop makes SketchUp fill it in, and that fill is the one
    # thing this mode must not leave behind. Two tests have to pass before
    # anything is erased, and the second one exists because the first alone
    # opens holes in solids:
    #
    # 1. The face's OUTER loop must BE the ring. A surrounding face that merely
    #    shares the ring — the wall around a recess — has a bigger outline and
    #    is left alone.
    # 2. No edge of it may carry exactly two faces. That is the skin test.
    #    Pushing a LOOSE face makes a box, and the box's new bottom sits on the
    #    ring and passes test 1 perfectly — erasing it would leave an
    #    open-bottomed box. On that bottom every edge carries two faces (bottom
    #    plus one side): a manifold pair, so the face is sealing something. An
    #    internal divider carries three (the wall either side of it plus
    #    itself), and an edge left holding nothing but the fill carries one.
    #    Neither of those is sealing anything, so both are safe to cut.
    # ------------------------------------------------------------
    def self.Na__PushPull__EraseRingFaces(edges, points_local)
        removed = 0
        seen    = []

        edges.each do |edge|
            next unless edge.valid?

            edge.faces.each { |face| seen << face unless seen.include?(face) }
        end

        seen.each do |face|
            next unless face.valid?

            outline = face.outer_loop.vertices.map { |vertex| vertex.position }
            next unless Na__InsertPrimatives.Na__PushPull__SameLoop?(outline, points_local)
            next unless Na__InsertPrimatives.Na__PushPull__DividerNotSkin?(face)

            face.erase!
            removed += 1
        end

        removed
    rescue StandardError
        removed
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Face Dividing the Solid Rather Than Sealing It?
    # An edge carrying exactly two faces is a manifold pair — this face is one
    # half of the skin there and cutting it would open the solid. Three means
    # the material already meets across that edge without this face's help, and
    # one means the edge is holding nothing else.
    # ------------------------------------------------------------
    def self.Na__PushPull__DividerNotSkin?(face)
        face.edges.none? { |edge| edge.faces.length == 2 }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are Two Outlines the Same Loop, Whatever Order They Are In?
    # Compared by distance rather than by a rounded key: a rounded key can
    # straddle its own boundary and call two identical points different, and
    # getting this wrong either leaves the fill face in or erases a real one.
    # ------------------------------------------------------------
    def self.Na__PushPull__SameLoop?(outline, points_local)
        return false unless outline.length == points_local.length

        points_local.all? do |wanted|
            outline.any? { |point| point.distance(wanted) < NA_PP_QUAD_TOL }
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL QUAD RING
# =============================================================================
