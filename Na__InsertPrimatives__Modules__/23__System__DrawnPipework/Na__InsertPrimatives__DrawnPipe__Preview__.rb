# =============================================================================
# NA INSERT PRIMATIVES - DRAWN PIPE PREVIEW
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPipe__Preview__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : What the Pipework tool draws before anything is built
# CREATED    : 2026
#
# DESCRIPTION:
# - Stateless, like the rest of the preview graphics: every function takes
#   the solve it draws. The preview IS the solve the builder will use, so the
#   bends, the tightened corners and the mitres on screen are the ones that
#   will be built.
# - The pipe is drawn in the volume amber (it is a solid being added), with
#   an outline round its ends, its mitre seams and the two ends of every bend,
#   so the bends read even where the fill is faint.
# - The route itself is a dotted guide line through the points the user
#   clicked or selected, and every corner a bend had to be tightened or
#   mitred to fit is labelled in the pinned-dimension orange.
# - Everything is global and drawn with View#draw, as the seam note at the top
#   of the preview graphics file explains.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'
require_relative 'Na__InsertPrimatives__DrawnPipe__Spec__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Pipe Preview Constants
    # -----------------------------------------------------------------------------

    NA_DRAWN_PIPE_PREVIEW_MAX_QUADS = 40_000                                  # <-- Beyond this only the centreline and the seams are drawn
    NA_DRAWN_PIPE_ROUTE_COLOR       = NA_DRAWN_GUIDE_COLOR
    NA_DRAWN_PIPE_FAILED_COLOR      = NA_DRAWN_REFUSED_BORDER_CLR
    NA_DRAWN_PIPE_SEAM_ROLES        = [:end, :mitre, :bend_edge].freeze       # <-- Rings the preview outlines

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Pipe Body
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Side Quad of a Solve as One Flat Point List for GL_QUADS
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__PreviewQuads(solved)
        rings  = solved[:rings]
        sides  = rings.first.length
        points = []

        pairs = (0...(rings.length - 1)).map { |ring| [ring, ring + 1, 0] }
        pairs << [rings.length - 1, 0, solved[:offset].to_i] if solved[:closed]

        pairs.each do |from, to, offset|
            sides.times do |j|
                [rings[from][j], rings[from][(j + 1) % sides],
                 rings[to][(j + 1 + offset) % sides], rings[to][(j + offset) % sides]].each do |xyz|
                    points << Geom::Point3d.new(xyz[0], xyz[1], xyz[2])
                end
            end
        end

        points
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Side Quads a Solve Has
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__QuadCount(solved)
        rings = solved[:rings]
        joins = solved[:closed] ? rings.length : rings.length - 1
        joins * rings.first.length
    end
    # ---------------------------------------------------------------

    # FUNCTION | Draw One Solved Pipe
    # ------------------------------------------------------------
    # `quads` is the cached result of PreviewQuads, or nil to skip the body
    # (a selection too big to shade every frame).
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__DrawSolved(view, solved, quads = nil)
        return unless solved && solved[:ok]

        if quads && !quads.empty?
            view.drawing_color = NA_DRAWN_VOLUME_FILL_COLOR
            view.draw(GL_QUADS, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(quads))
        end

        Na__InsertPrimatives.Na__DrawnPipe__DrawSeams(view, solved)
        Na__InsertPrimatives.Na__DrawnPipe__DrawCentreline(view, solved)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Outline the Rings That Mark a Change: Ends, Mitres, Bend Ends
    # The rings inside a bend and inside a drawn arc are left to the fill.
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__DrawSeams(view, solved)
        solved[:rings].each_with_index do |ring, index|
            role = solved[:roles][index]
            next unless NA_DRAWN_PIPE_SEAM_ROLES.include?(role)

            points = ring.map { |xyz| Geom::Point3d.new(xyz[0], xyz[1], xyz[2]) }
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, points, NA_DRAWN_VOLUME_BORDER_COLOR, 1)
            next unless solved[:bore] && role == :end

            bore = solved[:bore][index].map { |xyz| Geom::Point3d.new(xyz[0], xyz[1], xyz[2]) }
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, bore, NA_DRAWN_VOLUME_BORDER_COLOR, 2)  # <-- The bore, heavier: the pipe reads hollow
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Pipe's Centreline, Bends Included, Dashed
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__DrawCentreline(view, solved)
        points = solved[:centres].map { |xyz| Geom::Point3d.new(xyz[0], xyz[1], xyz[2]) }
        points << points.first if solved[:closed]
        return if points.length < 2

        view.line_stipple  = '-'
        view.line_width    = 1
        view.drawing_color = NA_DRAWN_VOLUME_BORDER_COLOR
        view.draw(GL_LINE_STRIP, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(points))
        view.line_stipple  = ''
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Route and Labels
    # -----------------------------------------------------------------------------

    # FUNCTION | The Route as Clicked or Selected: a Dotted Line and Its Points
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__DrawRoute(view, points, closed = false, color = nil)
        return unless points && points.length >= 1

        line = points.dup
        line << points.first if closed && points.length > 2

        if line.length >= 2
            view.line_stipple  = '.'
            view.line_width    = 1
            view.drawing_color = color || NA_DRAWN_PIPE_ROUTE_COLOR
            view.draw(GL_LINE_STRIP, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(line))
            view.line_stipple  = ''
        end

        view.draw_points(Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(points), 6, 2, color || NA_DRAWN_VOLUME_BORDER_COLOR)
    rescue StandardError
        nil                                                                   # <-- Never let a guide kill the whole draw pass
    end
    # ---------------------------------------------------------------

    # FUNCTION | Label Every Bend That Is Not the One That Was Asked For
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__LabelCorners(view, solved)
        return unless solved && solved[:ok]

        solved[:corners].each do |corner|
            next unless corner[:changed]

            text  = corner[:kind] == :bend ? "R#{Na__InsertPrimatives.Na__DrawnPipe__FormatMm(corner[:radius])}" : 'mitred'
            point = Geom::Point3d.new(corner[:point][0], corner[:point][1], corner[:point][2])
            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, point, text, 10, 6, NA_DRAWN_TEXT_LOCKED_COLOR)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Summary Card Beside the Cursor
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__DrawSummary(view, anchor, lines)
        return unless anchor

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor, lines.compact.reject(&:empty?))
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Centreline Length as Metres
    # ------------------------------------------------------------
    def self.Na__DrawnPipe__FormatMetres(value)
        format('%.2f m', value.to_f * NA_DRAWN_INCH_TO_MM / 1000.0)
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN PIPE PREVIEW
# =============================================================================
