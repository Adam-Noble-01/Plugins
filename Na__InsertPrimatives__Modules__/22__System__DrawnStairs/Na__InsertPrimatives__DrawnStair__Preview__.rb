# =============================================================================
# NA INSERT PRIMATIVES - DRAWN STAIR PREVIEW
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnStair__Preview__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : What the Drawn Staircase tool draws while a side is being chosen
#              and while the flight is being dragged
# CREATED    : 2026
#
# DESCRIPTION:
# - Stateless, like the rest of the preview graphics: every function takes the
#   block, the side frame and the solve it needs. The tool owns the state.
# - SIDE STAGE: the block in the volume amber, exactly as it looked a moment
#   ago, with the side under the cursor shaded blue, its top edge drawn heavy,
#   and an arrow pointing the way the flight will climb.
# - FLIGHT STAGE: the block becomes a dashed outline — what is being carved
#   away — and the stepped solid is drawn inside it in amber. A gold line runs
#   through the nosings at both ends of the stair with the pitch written on
#   it, and the summary card carries the rise, going, run and a Part K check.
# - Everything is global and drawn with View#draw, like the volume preview; see
#   the seam note at the top of the preview graphics file.
#
# COLOUR ROLES (new here; the rest come from the preview graphics palette):
#   side   blue   the side the stair will rise from, the chamfer's hover blue
#   pitch  gold   the line through the nosings the pitch is measured along
#   pass   green  a Part K check that passes; a failure uses the refusal red
#
# =============================================================================

require 'sketchup.rb'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'
require_relative 'Na__InsertPrimatives__DrawnStair__Geometry__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Stair Preview Palette
    # -----------------------------------------------------------------------------

    NA_DRAWN_STAIR_SIDE_COLOR  = Sketchup::Color.new(  0, 110, 235, 235)
    NA_DRAWN_STAIR_SIDE_WIDTH  = 5
    NA_DRAWN_STAIR_PITCH_COLOR = Sketchup::Color.new(235, 175,   0, 255)
    NA_DRAWN_STAIR_PITCH_WIDTH = 3
    NA_DRAWN_STAIR_PASS_COLOR  = Sketchup::Color.new( 25, 130,  55)

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Side Stage
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw the Block With the Side Under the Cursor Picked Out
    # ------------------------------------------------------------
    def self.Na__DrawnStair__DrawSideStage(view, box, frame, steps)
        return unless view && box && frame

        bottom, top = Na__InsertPrimatives.Na__DrawnStair__BoxRects(box)
        Na__InsertPrimatives.Na__DrawnPreview__DrawFilledBox(
            view, bottom, top, NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
        )

        Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
            view, Na__InsertPrimatives.Na__DrawnStair__SideFaceWorld(frame),
            NA_DRAWN_PLANE_FILL_COLOR, NA_DRAWN_PLANE_BORDER_COLOR
        )

        Na__InsertPrimatives.Na__DrawnStair__DrawSideEdge(view, frame)

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
            view, frame[:top_end],
            [
                'Stair rises from this side',
                "#{Na__InsertPrimatives.Na__DrawnStair__FormatMm(frame[:width])} wide · " \
                "up to #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(frame[:depth])} of run · " \
                "#{Na__InsertPrimatives.Na__DrawnStair__FormatMm(frame[:height])} high · #{steps} risers"
            ],
            14, -26, NA_DRAWN_TEXT_ACCENT_COLOR
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Heavy Blue Top Edge and the Arrow Pointing Up the Flight
    # ------------------------------------------------------------
    def self.Na__DrawnStair__DrawSideEdge(view, frame)
        ends = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace([frame[:top_start], frame[:top_end]])

        view.line_stipple  = ''
        view.line_width    = NA_DRAWN_STAIR_SIDE_WIDTH
        view.drawing_color = NA_DRAWN_STAIR_SIDE_COLOR
        view.draw_line(ends[0], ends[1])
        view.line_width    = 2

        Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(
            view, frame[:top_mid], frame[:inward], NA_DRAWN_STAIR_SIDE_COLOR
        )
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Flight Stage
    # -----------------------------------------------------------------------------

    # FUNCTION | Draw the Carved Block, the Pitch and the Numbers
    # ------------------------------------------------------------
    def self.Na__DrawnStair__DrawFlightStage(view, box, frame, solve)
        return unless view && box && frame && solve

        Na__InsertPrimatives.Na__DrawnStair__DrawBoxGuide(view, box)
        Na__InsertPrimatives.Na__DrawnStair__DrawSolid(view, frame, solve)

        # No run yet — the click that chose the side has not moved. The solid
        # is still the whole block, so the side and the way to drag are what
        # is worth showing.
        if solve[:run] <= NA_DRAWN_STAIR_MERGE_TOL.to_f
            Na__InsertPrimatives.Na__DrawnStair__DrawSideEdge(view, frame)
            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, frame[:top_end],
                ['Drag inward to set the flight', "#{solve[:steps]} risers — UP / DOWN to change"],
                14, -26, NA_DRAWN_TEXT_ACCENT_COLOR
            )
            return
        end

        Na__InsertPrimatives.Na__DrawnStair__DrawPitchLines(view, frame, solve)
        Na__InsertPrimatives.Na__DrawnStair__DrawFlightLabels(view, frame, solve)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Drawn Block as a Dashed Outline
    # What the flight is being carved out of, kept in view so the part that
    # disappears reads as disappearing rather than as never having been there.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__DrawBoxGuide(view, box)
        bottom, top = Na__InsertPrimatives.Na__DrawnStair__BoxRects(box)
        bottom      = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(bottom)
        top         = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(top)

        view.line_stipple  = '-'
        view.line_width    = 1
        view.drawing_color = NA_DRAWN_GUIDE_COLOR
        view.draw(GL_LINE_LOOP, bottom)
        view.draw(GL_LINE_LOOP, top)
        4.times { |index| view.draw_line(bottom[index], top[index]) }
        view.line_stipple  = ''
        view.line_width    = 2
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Stepped Solid, Shaded and Outlined
    # ------------------------------------------------------------
    # The same ProfileLocal the builder extrudes, mapped to both ends of the
    # stair. The ends are filled one step-column at a time because the
    # profile is concave; the risers, treads, landing, far face and base are
    # the profile's own segments swept across the width.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__DrawSolid(view, frame, solve)
        width   = frame[:width].to_f
        profile = Na__InsertPrimatives.Na__DrawnStair__ProfileLocal(solve)
        return if profile.length < 3

        near = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(
            Na__InsertPrimatives.Na__DrawnStair__ToWorld(frame, profile, 0.0)
        )
        far  = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(
            Na__InsertPrimatives.Na__DrawnStair__ToWorld(frame, profile, width)
        )

        view.drawing_color = NA_DRAWN_VOLUME_FILL_COLOR

        Na__InsertPrimatives.Na__DrawnStair__ColumnsLocal(solve).each do |column|
            view.draw(GL_QUADS, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(
                Na__InsertPrimatives.Na__DrawnStair__ToWorld(frame, column, 0.0)
            ))
            view.draw(GL_QUADS, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(
                Na__InsertPrimatives.Na__DrawnStair__ToWorld(frame, column, width)
            ))
        end

        count = near.length
        count.times do |index|
            following = (index + 1) % count
            view.draw(GL_QUADS, [near[index], near[following], far[following], far[index]])
        end

        view.line_stipple  = ''
        view.line_width    = 2
        view.drawing_color = NA_DRAWN_VOLUME_BORDER_COLOR
        view.draw(GL_LINE_LOOP, near)
        view.draw(GL_LINE_LOOP, far)
        count.times { |index| view.draw_line(near[index], far[index]) }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Gold Lines Through the Nosings, With the Pitch on One of Them
    # ------------------------------------------------------------
    # Drawn at both ends of the stair, as the pitch line is drawn on a stair
    # section. The degrees go on whichever end is nearer the eye, so the label
    # is not written across the far side of the flight.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__DrawPitchLines(view, frame, solve)
        near  = Na__InsertPrimatives.Na__DrawnStair__NosingLine(frame, solve, 0.0)
        far   = Na__InsertPrimatives.Na__DrawnStair__NosingLine(frame, solve, frame[:width])
        lines = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(near + far)

        view.line_stipple  = ''
        view.line_width    = NA_DRAWN_STAIR_PITCH_WIDTH
        view.drawing_color = NA_DRAWN_STAIR_PITCH_COLOR
        view.draw_line(lines[0], lines[1])
        view.draw_line(lines[2], lines[3])
        view.line_width    = 2

        labelled = Na__InsertPrimatives.Na__DrawnStair__NearerLine(view, near, far)

        Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
            view, labelled[0], labelled[1],
            "#{Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:pitch])}°",
            NA_DRAWN_TEXT_ACCENT_COLOR
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which of Two Lines Is Nearer the Camera
    # ------------------------------------------------------------
    def self.Na__DrawnStair__NearerLine(view, line_a, line_b)
        eye    = view.camera.eye
        centre = lambda { |line| Na__InsertPrimatives.Na__DrawnPreview__PointsCentre(line) }

        centre.call(line_a).distance(eye) <= centre.call(line_b).distance(eye) ? line_a : line_b
    rescue StandardError
        line_a
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Run Dimension and the Summary Card
    # ------------------------------------------------------------
    # The run is the number the drag is setting, so it is written along the
    # top of the flight from the chosen side to the landing edge, on a faint
    # dimension line. The card sits on the landing edge at the far end, and
    # its last line is the Part K check in green or red.
    # ------------------------------------------------------------
    def self.Na__DrawnStair__DrawFlightLabels(view, frame, solve)
        middle   = frame[:width].to_f * 0.5
        run_from = Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, 0.0,         solve[:height], middle)
        run_to   = Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, solve[:run], solve[:height], middle)

        Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, run_from, run_to)
        Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
            view, run_from, run_to,
            Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:run]),
            NA_DRAWN_TEXT_ACCENT_COLOR
        )

        anchor = Na__InsertPrimatives.Na__DrawnStair__FramePoint(frame, solve[:run], solve[:height], frame[:width])
        lines  = Na__InsertPrimatives.Na__DrawnStair__SummaryLines(solve)

        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor, lines)

        partk = Na__InsertPrimatives.Na__DrawnStair__PartK(solve)
        Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
            view, anchor,
            [Na__InsertPrimatives.Na__DrawnStair__PartKText(partk)],
            14, -26 + (lines.length * NA_DRAWN_TEXT_LINE_HEIGHT),
            partk[:ok] ? NA_DRAWN_STAIR_PASS_COLOR : NA_DRAWN_REFUSED_TEXT_COLOR
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Summary Card's Lines for a Solve
    # ------------------------------------------------------------
    def self.Na__DrawnStair__SummaryLines(solve)
        rise    = Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:rise])
        going   = Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:going])
        pitch   = Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:pitch])
        run     = Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:run])
        landing =
            if solve[:landing] > NA_DRAWN_STAIR_MERGE_TOL.to_f
                "landing #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:landing])}"
            else
                'no landing'
            end

        [
            "#{solve[:steps]} risers of #{rise} · #{solve[:steps] - 1} goings of #{going} mm",
            "Pitch #{pitch}° · run #{run} · #{landing}"
        ]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN STAIR PREVIEW
# =============================================================================
