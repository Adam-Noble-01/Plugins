# =============================================================================
# NA INSERT PRIMATIVES - DEEP PROJECT PREVIEW
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnProject__Preview__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnProjectPreview
# AUTHOR     : Noble Architecture
# PURPOSE    : Show the projection before the click, in the push tool's own
#              colours, with the target and the direction it is going by
# CREATED    : 2026
#
# DESCRIPTION:
# - The same picture Deep Push/Pull paints, so nothing has to be learnt:
#     blue      the face under the cursor, or the face taken
#     orange    the face where it will land, and the walls it will grow
#     red       the volume it will cut back, drawn THROUGH the model, because
#               every line of it is inside the solid (the 5.1.22 rule)
#     magenta   the quad ring QUADS will leave, and a loop cut's ring
# - Two things the push tool never needed:
#     the TARGET, shaded in the target blue (red, with the reason written on
#     it, when it cannot be reached), an object as its own box, a point as a
#     crosshair; and the DIRECTION, an edge lock drawn as a heavy magenta line
#     with an arrow on it, SketchUp's own colour for "parallel to this edge".
# - Every corner travels its own distance to a tilted target, so every rung
#   carries its own figure, thinned by the push tool's screen-space overlap
#   cull so a circle's two dozen rungs do not pile up into one smudge.
#
# All points are world, which is what View#draw reads in any context.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../05__PreviewGraphics/Na__InsertPrimatives__DrawnPreviewGraphics__'
require_relative 'Na__InsertPrimatives__DrawnProject__Geometry__'

module Na__InsertPrimatives

    module DrawnProjectPreview

        # -----------------------------------------------------------------------------
        # REGION | Hover (Idle)
        # -----------------------------------------------------------------------------

        # FUNCTION | Shade the Face Under the Cursor
        # ------------------------------------------------------------
        # The outline carries QUADS before the click, as the push tool's does:
        # it is a mode you can be in without realising.
        # ------------------------------------------------------------
        def na_pj__draw_hover(view)
            source = @na_pj_hover
            return unless source

            colours = self.class
            quads   = na_pj__quad_mode?

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, source[:triangles], colours::NA_PJ_HOVER_FILL)
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(
                view, source[:loops][0],
                quads ? colours::NA_PJ_QUAD_BORDER : colours::NA_PJ_HOVER_BORDER,
                quads ? 3 : 2
            )

            directed = na_pj__direct(source)
            lines    = ["#{source[:area]} m2 face", Na__InsertPrimatives.Na__DeepPick__PathLabel(source[:target])]
            lines << 'QUADS — keeps the start loop' if quads
            lines << directed[:words]
            lines << directed[:note] if directed[:note]

            last = Na__InsertPrimatives.Na__Project__Last
            lines << "dbl-click: on to #{last[:name]}" if last

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, source[:loops][0][0], lines)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Projection (Target Stage)
        # -----------------------------------------------------------------------------

        # FUNCTION | Everything the Target Stage Shows
        # ------------------------------------------------------------
        def na_pj__draw_projection(view)
            na_pj__draw_target(view)

            quads = na_pj__quad_mode?

            (@na_pj_directed || []).each_with_index do |source, index|
                solution = (@na_pj_solutions || [])[index]

                if solution && solution[:ok]
                    na_pj__draw_solution(view, source, solution, quads, true)
                else
                    na_pj__draw_waiting(view, source, solution)
                end
            end

            na_pj__draw_direction(view)
            na_pj__draw_travel_arrow(view)
            na_pj__draw_card(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Face Carried to Its Target
        # ------------------------------------------------------------
        # Out of the solid: the landed face in orange, its walls as rungs.
        # Into a solid: the volume removed, in the cutter red, through the
        # model — falling back to the depth-tested red when a corner is behind
        # the camera. QUADS and into the solid: a loop cut, so the face stays
        # where it is and only the ring is drawn where it will land.
        # ------------------------------------------------------------
        def na_pj__draw_solution(view, source, solution, quads, labels)
            colours = self.class
            near    = source[:loops][0]
            far     = solution[:loops][0]
            cutting = quads && solution[:way] == :in

            if cutting
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, source[:triangles], colours::NA_PJ_HOVER_FILL)
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, near, colours::NA_PJ_HOVER_BORDER, 1)

                source[:loops].each_with_index do |points, index|
                    na_pj__draw_rungs(view, points, solution[:loops][index], colours::NA_PJ_QUAD_BORDER)
                    Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, solution[:loops][index], colours::NA_PJ_QUAD_BORDER, 3)
                end
            else
                moved = source[:triangles].map do |points|
                    points.map { |point| Na__InsertPrimatives.Na__Project__Carry(source, solution, point) }
                end

                if solution[:way] == :in && source[:solid]
                    na_pj__draw_cut(view, source, solution, moved)
                elsif solution[:way] == :mixed
                    na_pj__draw_cut_and_extend(view, source, solution, moved, quads)
                else
                    Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(
                        view, near,
                        quads ? colours::NA_PJ_QUAD_BORDER : colours::NA_PJ_HOVER_BORDER,
                        quads ? 3 : 1
                    )
                    Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, moved, colours::NA_PJ_RESULT_FILL)

                    source[:loops].each_with_index do |points, index|
                        Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, solution[:loops][index], colours::NA_PJ_RESULT_BORDER, 2)
                        na_pj__draw_rungs(view, points, solution[:loops][index], colours::NA_PJ_RESULT_BORDER)
                    end
                end
            end

            na_pj__draw_travel_labels(view, source, solution) if labels
            far
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Volume a Cut Back Removes, Through the Model
        # ------------------------------------------------------------
        def na_pj__draw_cut(view, source, solution, moved)
            drawn = Na__InsertPrimatives.Na__DrawnPreview__DrawPrismOnTop(
                view, source[:loops][0], solution[:loops][0], moved,
                NA_DRAWN_CUTTER_XRAY_FILL, NA_DRAWN_CUTTER_BORDER_COLOR
            )
            return true if drawn

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, moved, NA_DRAWN_CUTTER_FILL_COLOR)
            source[:loops].each_with_index do |points, index|
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, solution[:loops][index], NA_DRAWN_CUTTER_BORDER_COLOR, 2)
                na_pj__draw_rungs(view, points, solution[:loops][index], NA_DRAWN_CUTTER_BORDER_COLOR)
            end
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Cut and Extend: Out to the Target in Orange, Back to It in Red
        # ------------------------------------------------------------
        # The landed face is half inside the solid, where the model's own faces
        # would hide it, so its outline and every rung are drawn on top in
        # screen space, as the push tool draws a cut. The fill stays
        # depth-tested: it shows where the face comes out into the open.
        # ------------------------------------------------------------
        def na_pj__draw_cut_and_extend(view, source, solution, moved, quads)
            colours = self.class

            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(
                view, source[:loops][0],
                quads ? colours::NA_PJ_QUAD_BORDER : colours::NA_PJ_HOVER_BORDER,
                quads ? 3 : 1
            )
            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, moved, colours::NA_PJ_RESULT_FILL)

            source[:loops].each_with_index do |points, index|
                landed = solution[:loops][index]
                out    = []
                back   = []

                points.each_with_index do |point, corner|
                    rung = [point, landed[corner]]
                    solution[:heights][index][corner].to_f < 0.0 ? back.concat(rung) : out.concat(rung)
                end

                ring = landed.each_with_index.flat_map { |point, corner| [point, landed[(corner + 1) % landed.length]] }

                na_pj__draw_on_top(view, ring, colours::NA_PJ_RESULT_BORDER, 2)
                na_pj__draw_on_top(view, out,  colours::NA_PJ_RESULT_BORDER, 1)
                na_pj__draw_on_top(view, back, NA_DRAWN_CUTTER_BORDER_COLOR, 2)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Line Segments Drawn Over Everything, Falling Back to Depth-Tested
        # ------------------------------------------------------------
        # Pairs of world points. In screen space when every point can be
        # projected honestly; otherwise (a point behind a perspective camera)
        # drawn as ordinary lines, so nothing is lost, only hidden.
        # ------------------------------------------------------------
        def na_pj__draw_on_top(view, pairs, colour, width)
            return if pairs.nil? || pairs.empty?

            view.line_stipple  = ''
            view.line_width    = width
            view.drawing_color = colour

            flat = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, pairs)
            if flat
                view.draw2d(GL_LINES, flat)
            else
                pairs.each_slice(2) do |start, finish|
                    view.draw_line(
                        Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(start),
                        Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(finish)
                    )
                end
            end

            view.line_width = 2
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Face Waiting for a Target, or Refused One
        # ------------------------------------------------------------
        def na_pj__draw_waiting(view, source, solution)
            colours = self.class
            refused = solution && !solution[:ok]

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, source[:triangles], colours::NA_PJ_HOVER_FILL)
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(
                view, source[:loops][0],
                refused ? NA_DRAWN_REFUSED_BORDER_CLR : colours::NA_PJ_HOVER_BORDER,
                2
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Lines Joining Each Start Corner to Where It Lands
        # ------------------------------------------------------------
        def na_pj__draw_rungs(view, from_loop, to_loop, color)
            return unless from_loop && to_loop

            side_from = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(from_loop)
            side_to   = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(to_loop)

            view.line_stipple  = ''
            view.line_width    = 1
            view.drawing_color = color

            side_from.each_with_index do |point, index|
                view.draw_line(point, side_to[index]) if side_to[index]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Each Corner's Own Travel, on Its Own Rung
        # ------------------------------------------------------------
        def na_pj__draw_travel_labels(view, source, solution)
            color =
                if    @na_pj_edge_lock then self.class::NA_PJ_EDGE_COLOR
                elsif @na_axis_lock    then Na__InsertPrimatives.Na__DrawnPreview__AxisColor(@na_axis_lock)
                else                        Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(false)
                end
            placed = []

            source[:loops].each_with_index do |points, loop_index|
                points.each_with_index do |point, index|
                    far = solution[:loops][loop_index][index]
                    next unless far
                    next unless na_pj__claim_label_slot(view, point, far, placed)

                    text = Na__InsertPrimatives.Na__DrawnFormat__Mm(solution[:travels][loop_index][index]).abs.to_s
                    text = "−#{text}" if solution[:way] == :mixed && solution[:heights][loop_index][index].to_f < 0.0
                    Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(view, point, far, text, color)
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take a Screen Slot for a Rung Label, or Report It Taken
        # The push tool's cull: two labels closer than NA_DRAWN_LABEL_MIN_GAP_PX
        # on screen are the same label twice.
        # ------------------------------------------------------------
        def na_pj__claim_label_slot(view, point, far, placed)
            midpoint = Geom::Point3d.new(
                (point.x.to_f + far.x.to_f) * 0.5,
                (point.y.to_f + far.y.to_f) * 0.5,
                (point.z.to_f + far.z.to_f) * 0.5
            )

            screen = view.screen_coords(Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(midpoint))
            wanted = [screen.x.to_f, screen.y.to_f]

            clash = placed.any? do |taken|
                dx = taken[0] - wanted[0]
                dy = taken[1] - wanted[1]
                Math.sqrt((dx * dx) + (dy * dy)) < NA_DRAWN_LABEL_MIN_GAP_PX
            end
            return false if clash

            placed << wanted
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Arrow From the Grabbed Point the Way the Face Will Go
        # ------------------------------------------------------------
        # Off the actual travel of the first corner when there is a target,
        # so it turns round for a cut back; with none yet, along the direction
        # the face would be carried, turned by the flip.
        # ------------------------------------------------------------
        def na_pj__draw_travel_arrow(view)
            return unless @na_point_a

            vector = nil

            (@na_pj_directed || []).each_with_index do |source, index|
                solution = (@na_pj_solutions || [])[index]
                next unless solution && solution[:ok]

                # The corner that travels furthest: on a tilted target one
                # corner can already be sitting on it, with no way to point.
                spans  = solution[:travels][0]
                widest = spans.index(spans.max) || 0
                vector = solution[:loops][0][widest] - source[:loops][0][widest]
                break
            end

            if vector.nil?
                first = (@na_pj_directed || []).first
                return unless first && first[:uniform] && first[:motions]

                motion = first[:motions][0][0]
                return unless motion

                vector = na_pj__sense_value < 0.0 ? motion.reverse : motion
            end
            return unless vector.length.to_f > 0.0

            Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(view, @na_point_a, vector.normalize)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Card Beside the Landed Face
        # ------------------------------------------------------------
        def na_pj__draw_card(view)
            sources   = @na_pj_directed || []
            solutions = @na_pj_solutions || []
            first     = sources.first
            return unless first

            unless @na_pj_target
                Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                    view, first[:loops][0][0],
                    [first[:words], 'Click what it should reach — a face, CTRL a point, SHIFT+TAB an object']
                )
                return
            end

            refusal = na_pj__refusal
            if refusal
                Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                    view, first[:loops][0][0],
                    ["Cannot reach #{@na_pj_target[:name]}", refusal],
                    14, -26, NA_DRAWN_REFUSED_TEXT_COLOR
                )
                return
            end

            solution = solutions.first
            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, solution[:loops][0][0], na_pj__card_lines(sources, solutions))
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Card Says About a Projection That Will Place
        # ------------------------------------------------------------
        def na_pj__card_lines(sources, solutions)
            first   = sources.first
            way     = solutions.first[:way]
            quads   = na_pj__quad_mode?
            travel  = Na__InsertPrimatives.Na__Project__TravelText(solutions.map { |solution| solution[:travels] })
            cutting = quads && way == :in

            head =
                if cutting
                    'Loop cut where the target crosses'
                elsif solutions.any? { |solution| solution[:way] == :mixed }
                    "Cut and extend — #{Na__InsertPrimatives.Na__Project__CutExtendText(solutions)}#{quads ? '  (quads)' : ''}"
                else
                    "Project #{travel} mm#{way == :in ? ' in' : ''}#{quads ? '  (quads)' : ''}"
                end
            head = "#{sources.length} faces — #{head}" if sources.length > 1

            reach = @na_pj_target[:kind] == :object ? "until it touches #{@na_pj_target[:name]}" : "on to #{@na_pj_target[:name]}"
            lines = [head, reach, first[:words]]
            lines << "offset #{na_pj__offset_words(@na_pj_offset)}" unless Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_pj_offset).zero?
            lines << 'looking back through the face (DOWN flips)' if @na_pj_target[:kind] == :object && na_pj__sense_value < 0.0
            lines << first[:note] if first[:note]
            lines
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Target and Direction
        # -----------------------------------------------------------------------------

        # FUNCTION | Shade What the Face Is Being Carried To
        # ------------------------------------------------------------
        def na_pj__draw_target(view)
            target = @na_pj_target
            return unless target

            refused = !na_pj__refusal.nil?

            case target[:kind]
            when :plane
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(
                    view, target[:triangles], refused ? NA_DRAWN_REFUSED_FILL_COLOR : NA_DRAWN_TARGET_FILL_COLOR
                )
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(
                    view, target[:loop], refused ? NA_DRAWN_REFUSED_BORDER_CLR : NA_DRAWN_TARGET_BORDER_COLOR, 2
                )
            when :point
                Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(
                    view, target[:point], nil, refused ? NA_DRAWN_REFUSED_BORDER_CLR : NA_DRAWN_TARGET_BORDER_COLOR
                )
                Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, @na_point_a, target[:point]) if @na_point_a
            when :object
                quads = target[:quads]
                return unless quads

                lines = refused ? [target[:name], na_pj__refusal] : [target[:name], 'the face stops where it first touches it']
                Na__InsertPrimatives.Na__DrawnPreview__DrawTargetHighlight(view, quads[0], quads[1], !refused, lines)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Locked Edge, and the Edge Under the Cursor
        # ------------------------------------------------------------
        def na_pj__draw_direction(view)
            colour = self.class::NA_PJ_EDGE_COLOR

            if @na_pj_edge_lock
                start, finish = @na_pj_edge_lock[:points]
                na_pj__draw_edge_line(view, start, finish, colour, 4, '')

                pointing = na_pj__edge_display_direction
                middle   = Geom::Point3d.linear_combination(0.5, start, 0.5, finish)
                Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(view, middle, pointing, colour) if pointing
            end

            hover = @na_pj_edge_hover
            return unless hover

            start, finish = hover[:points]
            refused = !hover[:refusal].nil?
            locked  = @na_pj_edge_lock && @na_pj_edge_lock[:key] == hover[:key]
            na_pj__draw_edge_line(view, start, finish, refused ? NA_DRAWN_REFUSED_BORDER_CLR : colour, 3, '-')

            lines =
                if refused then ["That edge #{hover[:refusal]}"]
                elsif locked then ['The locked edge — click or DOWN flips it']
                else ['Click or DOWN — project parallel to this edge', "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(hover[:length]).abs} mm, #{hover[:name]}"]
                end

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, Geom::Point3d.linear_combination(0.5, start, 0.5, finish), lines,
                14, -26, refused ? NA_DRAWN_REFUSED_TEXT_COLOR : nil
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Heavy Line Between Two World Points
        # ------------------------------------------------------------
        def na_pj__draw_edge_line(view, start, finish, colour, width, stipple)
            return unless start && finish

            view.line_stipple  = stipple
            view.line_width    = width
            view.drawing_color = colour
            view.draw_line(
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(start),
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(finish)
            )
            view.line_stipple  = ''
            view.line_width    = 2
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Draw Extents
        # -----------------------------------------------------------------------------

        # FUNCTION | Every Point the Preview Occupies
        # ------------------------------------------------------------
        def na_drawn__preview_points
            points = []
            points.concat(@na_pj_hover[:loops].flatten) if @na_pj_hover && @na_state == :idle

            (@na_pj_directed || []).each_with_index do |source, index|
                points.concat(source[:loops].flatten)

                solution = (@na_pj_solutions || [])[index]
                points.concat(solution[:loops].flatten) if solution && solution[:ok]
            end

            target = @na_pj_target
            if target
                points.concat(target[:loop]) if target[:loop]
                points << target[:point] if target[:point]
                points.concat(target[:quads].flatten) if target[:quads]
            end

            points.concat(@na_pj_edge_lock[:points])  if @na_pj_edge_lock
            points.concat(@na_pj_edge_hover[:points]) if @na_pj_edge_hover
            points.compact
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnProjectPreview module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PROJECT PREVIEW
# =============================================================================
