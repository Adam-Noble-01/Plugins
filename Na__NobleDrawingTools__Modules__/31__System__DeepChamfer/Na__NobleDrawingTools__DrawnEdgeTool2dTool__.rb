# =============================================================================
# NA NOBLE DRAWING TOOLS - EDGE TOOLS | PARALLEL (2D) CAMERA VARIANTS
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnEdgeTool2dTool__.rb
# NAMESPACE  : Na__NobleDrawingTools
# MODULE     : DrawnEdgeTool2d (mixed into the four classes below)
# CLASSES    : DrawnChamfer2dTool < DrawnChamferTool
#              DrawnFillet2dTool  < DrawnFilletTool
#              DrawnOgee2dTool    < DrawnOgeeTool
#              DrawnOvolo2dTool   < DrawnOvoloTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Chamfer, fillet, ogee or ovolo an edge from an elevation, by
#              hovering the CORNER you can see rather than the edge you cannot
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Push Pull 2D grabs the wall behind a line. These grab the edge behind
#   a corner. In an elevation the edge to round runs straight into the screen:
#   it draws as a point, the corner of the profile, so the 3D tools had
#   nothing to hover and took the profile's own line instead.
# - Each class is its 3D profile with this one module on top. The module
#   replaces how an edge is FOUND and how it is DRAWN, through the seams the
#   chamfer tool keeps for it (na_drawn__edge_at, na_drawn__batch_for,
#   na_drawn__draw_summary_card), and inherits everything else verbatim: the
#   solve, the scrub, the limit, CTRL vertex snapping, the mitres and stops,
#   the commit, retype, double-click repeat, TAB, SHIFT+TAB and undo.
#
# WHAT HOVERING DOES (see the pick file for how):
# - Near a corner with an edge running into the screen: that edge, and every
#   edge carrying it straight on (a run split along its length is cut as one,
#   meeting itself full width). A blue ring marks the corner and two ticks
#   run along its two faces, so the corner being cut is plain before a click.
# - Anywhere else: the edge under the cursor, exactly as in 3D.
# - SHIFT+click a corner banks its whole run; SHIFT+click it again un-banks it.
#
# WHAT THE PREVIEW SHOWS:
# - The cut seen end-on IS the profile, so it is drawn as one: the corner it
#   removes shaded on top at the near end (the far end sits exactly behind it
#   and is not drawn twice), the profile line drawn heavy over it, and the
#   summary card set off the corner, clear of the setback dimensions.
# - An edge that does not run into the screen previews as in 3D.
#
# CAMERA SWITCHING IS AUTOMATIC:
# - One command, one shortcut and one popup button per profile, as before. The
#   camera decides which class starts (AppCore ModeSwitch), and an idle mouse
#   move hands over when it changes (Na__EdgeTool2d__HandoverIfCameraFlipped,
#   called first in the chamfer tool's onMouseMove). SHIFT+TAB and the menus
#   stay in 2D while the camera is parallel.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__NobleDrawingTools__DrawnChamferTool__'
require_relative '../32__System__DeepOgee/Na__NobleDrawingTools__DrawnOgeeTool__'
require_relative '../33__System__DeepFillet/Na__NobleDrawingTools__DrawnFilletTool__'
require_relative '../34__System__DeepOvolo/Na__NobleDrawingTools__DrawnOvoloTool__'
require_relative 'Na__NobleDrawingTools__DrawnEdgeTool2d__Pick__'

module Na__NobleDrawingTools

    # @delegate: Na__NobleDrawingTools__DrawnEdgeTool2d__Pick__.rb

    # -----------------------------------------------------------------------------
    # REGION | Drawing Constants
    # -----------------------------------------------------------------------------

    NA_ET2D_HOVER_COLOR   = Sketchup::Color.new(  0, 110, 235, 235)           # <-- The chamfer tool's own hover blue
    NA_ET2D_BANKED_COLOR  = Sketchup::Color.new(226, 118,   0, 255)           # <-- The chamfer tool's own bank amber
    NA_ET2D_REFUSED_COLOR = Sketchup::Color.new(200,  30,  30, 235)           # <-- A corner that cannot take the cut
    NA_ET2D_RING_PX       = 9.0                                               # <-- Radius of the ring round a corner, on screen
    NA_ET2D_RING_SIDES    = 20
    NA_ET2D_BRACKET_PX    = 34.0                                              # <-- How far the ticks run along each face, on screen
    NA_ET2D_LINE_WIDTH    = 3
    NA_ET2D_PROFILE_WIDTH = 3                                                 # <-- The profile seen end-on, over the shading
    NA_ET2D_LABEL_PAD_PX  = 18.0                                              # <-- Clear space between a label block and its corner

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # MODULE | The 2D Half of Every Edge Tool
    # =============================================================================

    module DrawnEdgeTool2d

        # -----------------------------------------------------------------------------
        # REGION | Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title: the Profile's Own, Marked 2D
        # The popup key is NOT changed: to the user this is the same tool,
        # adapting, so the popup lights the same button either way.
        # ------------------------------------------------------------
        def na_drawn__tool_title
            "#{super} 2D"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner: the 2D Lines First, Then the Profile's
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'PARALLEL CAMERA MODE — an edge running into the screen shows as a CORNER',
                'Hover a CORNER: the edge behind it is the one cut — a run split along its length comes whole',
                'Hover a line away from the corners and that edge is cut, as in 3D',
                'SHIFT+click a corner banks its whole run — click it again to drop it',
                'Orbit into perspective and the 3D tool takes back over on its own'
            ] + super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Describe the Grabbed Edge, or Say What to Hover
        # ------------------------------------------------------------
        def na_drawn__plane_description
            return super if @na_ch_target

            'Parallel camera — hover a corner'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Finding the Edge — a Corner Gives the Edge Behind It
        # -----------------------------------------------------------------------------

        # FUNCTION | The Edge Target Under the Cursor (the Chamfer Tool's Seam)
        # ------------------------------------------------------------
        # Under a parallel camera, the edge behind a corner within reach, else
        # the edge under the cursor; nil with the reason kept for the status
        # line. The camera is asked here too, not only by the handover: a press
        # can land before the first mouse move after a scene change.
        # ------------------------------------------------------------
        def na_drawn__edge_at(view, x, y)
            @na_et2d_refusal = nil
            return super unless Na__NobleDrawingTools.Na__PushPull2d__ParallelCamera?(view)

            resolved = Na__NobleDrawingTools.Na__EdgeTool2d__ResolveAt(view, x, y)
            return resolved[:target] if resolved && resolved[:target]

            @na_et2d_refusal = resolved ? resolved[:refusal] : nil
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Grab the Edge, Then Anchor the Drag on the Visible Corner
        # ------------------------------------------------------------
        # The chamfer tool anchors on the point of the edge nearest the pick
        # ray. An edge running into the screen is PARALLEL to every pick ray,
        # so that point is anywhere along it; the corner the user aimed at is
        # the honest anchor. Only the crosshair and CTRL's vertex snap read it,
        # and the snap measures across the edge, so no size changes.
        # ------------------------------------------------------------
        def na_drawn__grab_edge(view, x, y, target = nil)
            unless target
                target = na_drawn__edge_at(view, x, y)

                unless target
                    UI.beep
                    Sketchup::set_status_text(@na_et2d_refusal || 'No corner or edge under the cursor', SB_PROMPT)
                    return false
                end
            end

            grabbed = super(view, x, y, target)

            corner = na_et2d__corner(target)
            @na_ch_anchor = corner if grabbed && corner
            grabbed
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Batch a Grab Cuts: the Chamfer Tool's, Plus the Run
        # ------------------------------------------------------------
        def na_drawn__batch_for(target)
            batch = super

            na_et2d__run_of(target).each do |member|
                next unless member[:edge] && member[:edge].valid?
                next if batch.any? { |held| held[:edge] == member[:edge] && held[:path] == member[:path] }

                batch << member
            end

            batch
        end
        # ---------------------------------------------------------------

        # FUNCTION | SHIFT+Click a Corner Banks Its Whole Run, or Drops It
        # ------------------------------------------------------------
        # A run of one is the chamfer tool's own toggle, with every check it
        # makes. A longer run goes in or out together: all banked already and
        # it comes out, otherwise every member that can take the cut goes in.
        # ------------------------------------------------------------
        def na_drawn__toggle_multi_edge(view, x, y)
            target = na_drawn__edge_at(view, x, y)

            unless target
                UI.beep
                Sketchup::set_status_text(@na_et2d_refusal || 'No corner or edge under the cursor to add', SB_PROMPT)
                return false
            end

            run = na_et2d__run_of(target)
            return super if run.length < 2

            if run.all? { |member| na_drawn__multi_index_of(member) }
                run.each do |member|
                    index = na_drawn__multi_index_of(member)
                    @na_ch_multi.delete_at(index) if index
                end

                Sketchup::set_status_text("Run of #{run.length} edges removed — #{@na_ch_multi.length} banked", SB_PROMPT)
                return true
            end

            if target[:locked]
                UI.beep
                Sketchup::set_status_text('That edge is inside a locked group or component', SB_PROMPT)
                return false
            end

            added = 0
            run.each do |member|
                next if na_drawn__multi_index_of(member)
                next unless member[:face_count] == 2 && na_drawn__solve_member(member, 1.0)

                @na_ch_multi << member
                added += 1
            end

            if added.zero?
                UI.beep
                Sketchup::set_status_text("This run cannot take #{na_drawn__cut_phrase}", SB_PROMPT)
                return false
            end

            Sketchup::set_status_text(
                "Corner's run of #{run.length} banked — #{@na_ch_multi.length} edge#{@na_ch_multi.length == 1 ? '' : 's'} in all, click one to drag them all",
                SB_PROMPT
            )
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Line
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # Mid-drag, and with preselected or banked edges, the profile's own.
        # ------------------------------------------------------------
        def na_drawn__status_detail
            return super unless @na_state == :idle && !na_ps__active?

            adjust = na_revise__status_hint
            arris  = na_et2d__arris(@na_ch_target)

            if arris && @na_ch_target[:face_count] == 2
                length = Na__NobleDrawingTools.Na__DrawnFormat__Mm(arris[:length_world]).abs
                count  = (arris[:members] || []).length
                run    = count > 1 ? " (a run of #{count})" : ''
                return "Corner — the #{length} mm edge behind it#{run}: click to grab, SHIFT+click to bank#{na_drawn__focus_hint}#{adjust}"
            end

            return super if @na_ch_target || @na_ch_multi.any?
            return "#{@na_et2d_refusal}#{adjust}" if @na_et2d_refusal

            "Hover a corner to #{na_drawn__cut_verb} the edge running into the screen behind it, or a line to #{na_drawn__cut_verb} that edge#{na_drawn__focus_hint}#{adjust}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Hover and Bank Drawing
        # -----------------------------------------------------------------------------

        # FUNCTION | Mark the Corner Under the Cursor and the Faces It Joins
        # ------------------------------------------------------------
        # The edge itself is a dot from here, so it is not what is drawn: a ring
        # round the corner, a tick along each of its two faces, and the card
        # off to the side of the corner away from them. Red when the edge
        # cannot take the cut. A plain edge is highlighted as in 3D.
        # ------------------------------------------------------------
        def na_drawn__draw_edge_highlight(view)
            target = @na_ch_target
            arris  = na_et2d__arris(target)
            return super unless arris && target[:edge] && target[:edge].valid?

            usable = target[:face_count] == 2
            color  = usable ? NA_ET2D_HOVER_COLOR : NA_ET2D_REFUSED_COLOR
            corner = arris[:corner]

            na_et2d__draw_ring(view, corner, color, NA_ET2D_RING_PX)
            na_et2d__draw_bracket(view, corner, arris[:face_dirs], color)

            length_mm = Na__NobleDrawingTools.Na__DrawnFormat__Mm(arris[:length_world]).abs
            count     = (arris[:members] || []).length

            lines = ["#{length_mm} mm edge behind this corner"]
            lines << "a run of #{count} edges, cut as one" if count > 1
            lines << (usable ? Na__NobleDrawingTools.Na__DeepPick__PathLabel(target) : "#{target[:face_count]} faces — cannot #{na_drawn__cut_verb}")
            lines << na_ps__highlight_note if @na_state == :idle && na_ps__active?

            away = na_et2d__outward(view, corner, arris[:face_dirs], arris[:convex] != false) || [0.7071, -0.7071]
            na_et2d__draw_label_outside(view, corner, away, lines, usable ? nil : NA_DRAWN_REFUSED_TEXT_COLOR)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Banked Edges: the Chamfer Tool's Lines, Plus a Ring Where One Is a Dot
        # ------------------------------------------------------------
        # A banked edge running into the screen draws as a dot, which is no
        # way to show a selection. Its near end gets a smaller amber ring,
        # once per corner however many edges of a run are banked behind it.
        # ------------------------------------------------------------
        def na_drawn__draw_banked_edges(view)
            super
            return if @na_ch_multi.empty?
            return unless Na__NobleDrawingTools.Na__PushPull2d__ParallelCamera?(view)

            begin
                seen = {}

                @na_ch_multi.each do |banked|
                    next unless Na__NobleDrawingTools.Na__EdgeTool2d__TargetEndOn?(view, banked)

                    near   = Na__NobleDrawingTools.Na__EdgeTool2d__NearEnd(view, banked)
                    screen = view.screen_coords(near)
                    key    = [screen.x.to_f.round, screen.y.to_f.round]
                    next if seen[key]

                    seen[key] = true
                    na_et2d__draw_ring(view, near, NA_ET2D_BANKED_COLOR, NA_ET2D_RING_PX - 2.0)
                end
            rescue StandardError
                nil                                                           # <-- Never let a decoration kill the whole draw pass
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview — the Cut Seen End-On Is the Profile
        # -----------------------------------------------------------------------------

        # FUNCTION | One End of a Cut: On Top at the Near End, Not at All at the Far
        # ------------------------------------------------------------
        # End-on, the cap at the near end lies in the plane of the end face
        # and fights it for the depth test, and the far cap sits exactly
        # behind it. So the near cap alone is drawn, on top in screen space,
        # in the colours the chamfer tool gives it (the removed corner blue,
        # a stop amber). Mitred and through ends have no cap, as ever. An edge
        # that does not run into the screen is the chamfer tool's business.
        # ------------------------------------------------------------
        def na_drawn__draw_end_cap(view, solve, end_index, points)
            return super unless na_et2d__end_on_solve?(view, solve)
            return if solve[end_index.zero? ? :mitre0 : :mitre1] || solve[end_index.zero? ? :through0 : :through1]
            return unless end_index == na_et2d__near_end(view, solve)
            return super unless points && points.length >= 3 && points.all?

            stopped   = solve[end_index.zero? ? :stop0 : :stop1]
            triangles = []
            (1...(points.length - 1)).each do |index|
                triangles << points[0] << points[index] << points[index + 1]
            end

            drawn = Na__NobleDrawingTools.Na__DrawnPreview__DrawSurfaceOnTop(
                view, [], triangles, [points + [points.first]],
                stopped ? NA_DRAWN_VOLUME_XRAY_FILL    : NA_DRAWN_PLANE_FILL_COLOR,
                stopped ? NA_DRAWN_VOLUME_BORDER_COLOR : NA_DRAWN_PLANE_BORDER_COLOR
            )
            super unless drawn
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Cut, Then Its Profile Heavy Where It Is Seen End-On
        # ------------------------------------------------------------
        # Seen end-on, the cut's surface is edge-on and draws as nothing but
        # its outline, and that outline IS the profile: the chamfer's line,
        # the fillet's arc, the ogee's S. Drawn once more on top, heavier, at
        # the near end, it reads as the shape being cut into the corner.
        # ------------------------------------------------------------
        def na_drawn__draw_cut_faces(view, solve)
            super
            return unless na_et2d__end_on_solve?(view, solve)

            begin
                world   = solve[:world]
                near    = na_et2d__near_end(view, solve)
                profile = world[near.zero? ? :profile0 : :profile1]
                profile = (near.zero? ? [world[:a0], world[:b0]] : [world[:a1], world[:b1]]) unless profile && profile.length >= 2
                return unless profile.all?

                projected = Na__NobleDrawingTools.Na__DrawnPreview__ScreenPoints(view, profile)
                return unless projected && projected.length >= 2

                view.line_stipple  = ''
                view.line_width    = NA_ET2D_PROFILE_WIDTH
                view.drawing_color = NA_DRAWN_VOLUME_BORDER_COLOR
                view.draw2d(GL_LINE_STRIP, projected)
                view.line_width    = 2
            rescue StandardError
                nil                                                           # <-- Never let a decoration kill the whole draw pass
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Summary Card, Set Off the Corner (the Chamfer Tool's Seam)
        # ------------------------------------------------------------
        # In 3D the card hangs off the far end of the cut. End-on that end is
        # the near end, on top of the setback dimensions, so the card goes the
        # other way: off the corner into the open, as far as its own size and
        # (on an inside corner, where the fill is in the open) the cut's.
        # ------------------------------------------------------------
        def na_drawn__draw_summary_card(view, solve, lines)
            return super unless na_et2d__end_on_solve?(view, solve)

            world  = solve[:world]
            near   = na_et2d__near_end(view, solve)
            corner = near.zero? ? world[:v0] : world[:v1]
            side_a = near.zero? ? world[:a0] : world[:a1]
            side_b = near.zero? ? world[:b0] : world[:b1]
            return super unless corner && side_a && side_b

            dirs = [side_a - corner, side_b - corner]
            return super unless dirs.all? { |direction| direction.length > 0 }

            convex = solve[:convex] != false
            away   = na_et2d__outward(view, corner, dirs.map(&:normalize), convex)
            return super unless away

            reach = convex ? 0.0 : [na_et2d__screen_gap(view, corner, side_a), na_et2d__screen_gap(view, corner, side_b)].max
            na_et2d__draw_label_outside(view, corner, away, lines, nil, reach)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Helpers
        # -----------------------------------------------------------------------------

        # FUNCTION | A Target's Corner Record, or nil for a Plain Edge
        # ------------------------------------------------------------
        def na_et2d__arris(target)
            target ? target[:arris] : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Edge Target in a Target's Run ([] for a Plain Edge)
        # ------------------------------------------------------------
        def na_et2d__run_of(target)
            arris = na_et2d__arris(target)
            arris ? (arris[:members] || []) : []
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Target's Visible Corner, World, or nil
        # ------------------------------------------------------------
        def na_et2d__corner(target)
            arris = na_et2d__arris(target)
            arris ? arris[:corner] : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Solved Cut Seen End-On From Here?
        # ------------------------------------------------------------
        def na_et2d__end_on_solve?(view, solve)
            world = solve ? solve[:world] : nil
            return false unless world && world[:v0] && world[:v1]
            return false unless Na__NobleDrawingTools.Na__PushPull2d__ParallelCamera?(view)

            Na__NobleDrawingTools.Na__EdgeTool2d__EndOn?(
                world[:v1] - world[:v0], Na__NobleDrawingTools.Na__PushPull2d__CameraDirection(view)
            )
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which End of a Solved Cut Is Nearer the Camera (0 or 1)
        # ------------------------------------------------------------
        def na_et2d__near_end(view, solve)
            world = solve[:world]

            Na__NobleDrawingTools.Na__EdgeTool2d__Depth(view, world[:v0]) <= Na__NobleDrawingTools.Na__EdgeTool2d__Depth(view, world[:v1]) ? 0 : 1
        end
        # ---------------------------------------------------------------

        # FUNCTION | Unit Screen Direction a World Direction Takes From a Point
        # ------------------------------------------------------------
        def na_et2d__screen_dir(view, origin, direction)
            reach = view.pixels_to_model(NA_DRAWN_ARROW_PIXELS, origin).to_f
            return nil unless reach > 0.0

            here   = view.screen_coords(origin)
            there  = view.screen_coords(origin.offset(direction, reach))
            dx     = there.x.to_f - here.x.to_f
            dy     = there.y.to_f - here.y.to_f
            length = Math.sqrt((dx * dx) + (dy * dy))
            return nil if length < 1.0

            [dx / length, dy / length]
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pixels Between Two World Points on Screen
        # ------------------------------------------------------------
        def na_et2d__screen_gap(view, point_a, point_b)
            here  = view.screen_coords(point_a)
            there = view.screen_coords(point_b)
            Math.sqrt(((there.x.to_f - here.x.to_f) ** 2) + ((there.y.to_f - here.y.to_f) ** 2))
        rescue StandardError
            0.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Unit Screen Direction Off a Corner Into the Open, or nil
        # ------------------------------------------------------------
        # Between the two faces is the material on an outside corner and the
        # open on an inside one, so the open lies against their bisector on
        # one and along it on the other. nil when the faces run opposite ways
        # on screen and there is no bisector to read.
        # ------------------------------------------------------------
        def na_et2d__outward(view, corner, face_dirs, convex)
            return nil unless face_dirs && face_dirs.length == 2

            side_a = na_et2d__screen_dir(view, corner, face_dirs[0])
            side_b = na_et2d__screen_dir(view, corner, face_dirs[1])
            return nil unless side_a && side_b

            sum_x  = side_a[0] + side_b[0]
            sum_y  = side_a[1] + side_b[1]
            length = Math.sqrt((sum_x * sum_x) + (sum_y * sum_y))
            return nil if length < 1.0e-3

            sign = convex ? -1.0 : 1.0
            [sign * sum_x / length, sign * sum_y / length]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Ring Round a World Point, in Screen Space
        # ------------------------------------------------------------
        def na_et2d__draw_ring(view, centre, color, radius_px)
            screen = view.screen_coords(centre)
            points = (0...NA_ET2D_RING_SIDES).map do |index|
                angle = (2.0 * Math::PI * index) / NA_ET2D_RING_SIDES
                Geom::Point3d.new(
                    screen.x.to_f + (radius_px * Math.cos(angle)),
                    screen.y.to_f + (radius_px * Math.sin(angle)),
                    0
                )
            end

            view.line_stipple  = ''
            view.line_width    = NA_ET2D_LINE_WIDTH
            view.drawing_color = color
            view.draw2d(GL_LINE_LOOP, points)
            view.line_width    = 2
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Tick From the Ring Along Each of the Corner's Two Faces
        # ------------------------------------------------------------
        def na_et2d__draw_bracket(view, corner, face_dirs, color)
            return unless face_dirs

            screen   = view.screen_coords(corner)
            segments = []

            face_dirs.each do |direction|
                along = na_et2d__screen_dir(view, corner, direction)
                next unless along

                segments << Geom::Point3d.new(screen.x.to_f + (along[0] * NA_ET2D_RING_PX),    screen.y.to_f + (along[1] * NA_ET2D_RING_PX),    0)
                segments << Geom::Point3d.new(screen.x.to_f + (along[0] * NA_ET2D_BRACKET_PX), screen.y.to_f + (along[1] * NA_ET2D_BRACKET_PX), 0)
            end
            return if segments.empty?

            view.line_stipple  = ''
            view.line_width    = NA_ET2D_LINE_WIDTH
            view.drawing_color = color
            view.draw2d(GL_LINES, segments)
            view.line_width    = 2
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Text Block Off a Corner, Clear of It by Its Own Size
        # ------------------------------------------------------------
        # Centred on a point pushed along `away` (a unit screen direction) far
        # enough that the whole block clears the corner by the padding, plus
        # reach_px for anything drawn out from the corner that way.
        # ------------------------------------------------------------
        def na_et2d__draw_label_outside(view, corner, away, lines, color = nil, reach_px = 0.0)
            screen        = view.screen_coords(corner)
            width, height = Na__NobleDrawingTools.Na__DrawnPreview__TextBlockSize(lines)

            push = NA_ET2D_LABEL_PAD_PX + reach_px.to_f +
                   (away[0].abs * width  * 0.5) +
                   (away[1].abs * height * 0.5)

            Na__NobleDrawingTools.Na__DrawnPreview__DrawCentredScreenText(
                view,
                screen.x.to_f + (away[0] * push),
                screen.y.to_f + (away[1] * push),
                lines, color
            )
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnEdgeTool2d module


    # -----------------------------------------------------------------------------
    # REGION | The Four Parallel Camera Variants
    # -----------------------------------------------------------------------------

    # CLASS | Deep Chamfer for a Parallel Camera
    # ------------------------------------------------------------
    class DrawnChamfer2dTool < DrawnChamferTool
        include Na__NobleDrawingTools::DrawnEdgeTool2d
    end
    # ---------------------------------------------------------------

    # CLASS | Deep Fillet for a Parallel Camera
    # ------------------------------------------------------------
    class DrawnFillet2dTool < DrawnFilletTool
        include Na__NobleDrawingTools::DrawnEdgeTool2d
    end
    # ---------------------------------------------------------------

    # CLASS | Deep Ogee for a Parallel Camera
    # ------------------------------------------------------------
    class DrawnOgee2dTool < DrawnOgeeTool
        include Na__NobleDrawingTools::DrawnEdgeTool2d
    end
    # ---------------------------------------------------------------

    # CLASS | Deep Ovolo for a Parallel Camera
    # ------------------------------------------------------------
    class DrawnOvolo2dTool < DrawnOvoloTool
        include Na__NobleDrawingTools::DrawnEdgeTool2d
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Force a 2D Edge Tool (Ruby Console, for Checking Behaviour)
    # ------------------------------------------------------------
    # The normal route is the camera-aware command. Forced under a perspective
    # camera, the first mouse move hands straight back to the 3D tool.
    #   Na__NobleDrawingTools.Na__NobleDrawingTools__DeepEdgeTool2d(:fillet)
    # ------------------------------------------------------------
    def self.Na__NobleDrawingTools__DeepEdgeTool2d(profile = :chamfer)
        model = Sketchup.active_model
        return nil unless model

        names = NA_ET2D_CLASSES[profile.to_s.to_sym]
        klass = names ? Na__NobleDrawingTools.Na__EdgeTool2d__Class(names[1]) : nil
        return nil unless klass

        tool = klass.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF EDGE TOOLS 2D VARIANTS
# =============================================================================
