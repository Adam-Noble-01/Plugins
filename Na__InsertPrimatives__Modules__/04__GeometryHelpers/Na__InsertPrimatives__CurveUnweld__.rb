# =============================================================================
# NA INSERT PRIMATIVES - CURVE UNWELD (EXPLODE, MOVE, WELD BACK)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__CurveUnweld__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Let a vertex-by-vertex move reach welded curves without SketchUp
#              reshaping the whole curve under it
# CREATED    : 2026
#
# DESCRIPTION:
# - A welded curve (an arc, a circle, a polygon, a welded run of edges) is
#   one object to SketchUp. Move any of its vertices with
#   transform_by_vectors or transform_entities and SketchUp "tries to be
#   smart and smoothly change the whole curve" (ene_su, SketchUp forum,
#   "Arc / Curve Transformation in Ruby"): the curve is re-fitted round the
#   moved points, and a batch of vertices moved by different vectors warps
#   it. Both transform methods do it. The forum's answers are to leave the
#   curve's interior vertices out (no good: they must move), to give each
#   curve its own Curve#move_vertices call (no good when two curves share a
#   vertex: it is moved twice), or to explode, move and weld back.
# - This is the last: every curve touching a moving vertex is exploded just
#   before the move, so its edges are plain edges that move exactly, and the
#   same edges are welded back into a curve afterwards (Entities#weld,
#   SketchUp 2020.1+), so it still selects and reads as one curve.
# - An ArcCurve comes back as a plain Curve: once its points have moved
#   unevenly it is no longer a circle, so it can no longer be an arc. Where
#   weld is unavailable the curve is left exploded, which is what the user
#   did by hand before this.
# - Called inside the caller's operation, in the context being edited, so
#   the explode and the weld are part of the one undo step.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Curve Unweld
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Curve With an Edge at One of These Vertices
    # ------------------------------------------------------------
    # An end vertex counts as much as an interior one: moving the end of an
    # arc re-fits the arc just the same.
    # ------------------------------------------------------------
    def self.Na__CurveUnweld__CurvesAt(vertices)
        curves = {}

        (vertices || []).each do |vertex|
            next unless vertex && vertex.valid?

            vertex.edges.each do |edge|
                curve = edge.curve
                next unless curve && curve.valid?

                curves[curve.entityID] ||= curve
            end
        end

        curves.values
    end
    # ---------------------------------------------------------------

    # FUNCTION | Explode Those Curves; Return Their Edges to Weld Back Later
    # ------------------------------------------------------------
    def self.Na__CurveUnweld__Explode(vertices)
        Na__InsertPrimatives.Na__CurveUnweld__CurvesAt(vertices).map do |curve|
            edges = curve.edges.to_a
            next nil if edges.empty?

            edges.first.explode_curve                                     # <-- Any one edge explodes the whole curve
            edges
        end.compact
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "CURVE UNWELD: explode failed — #{error.message}"
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Weld Each Exploded Curve Back; Returns the Curves Made
    # ------------------------------------------------------------
    # Only the edges still standing and still loose in `entities` go back:
    # a move can merge two vertices and take an edge with them, and weld
    # refuses edges of another collection. A curve left with a single edge
    # stays an edge.
    # ------------------------------------------------------------
    def self.Na__CurveUnweld__Reweld(entities, chains)
        return 0 if chains.nil? || chains.empty?
        return 0 unless entities.respond_to?(:weld)

        owner = entities.parent
        made  = 0

        chains.each do |edges|
            live = edges.select { |edge| edge.valid? && edge.curve.nil? && edge.parent == owner }
            next if live.length < 2

            made += (entities.weld(live) || []).length
        end

        made
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "CURVE UNWELD: weld back failed — #{error.message}"
        0
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF CURVE UNWELD
# =============================================================================
