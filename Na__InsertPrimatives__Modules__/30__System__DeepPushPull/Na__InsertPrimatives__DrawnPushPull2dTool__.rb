# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL TOOL | PARALLEL (2D) CAMERA VARIANT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull2dTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnPushPull2dTool  <  DrawnPushPullTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Push/pull while working in parallel projection, by grabbing the
#              EDGE you can see rather than the face you cannot
# CREATED    : 2026
#
# DESCRIPTION:
# - The 3D tool is unchanged and still does the work. This subclass replaces
#   exactly two things — how a target is CHOSEN and how it is DRAWN — and
#   inherits the distance maths, axis lock, quad ring, VCB, undo chaining and
#   the whole commit path from it verbatim.
#
# WHY A SEPARATE TOOL AT ALL:
# - In an elevation the wall you want to extend is edge-on to the camera. It
#   renders as a LINE, so there is no face to hover and the 3D tool has nothing
#   to grab. The face you can hover is the elevation itself, whose normal points
#   straight at the camera: pushing it moves geometry directly toward or away
#   from you, which is both invisible on screen and never what was wanted.
# - So the pick is inverted. Hover the line, and the tool walks from that edge
#   to the face behind it — the one standing perpendicular to the screen — and
#   pushes THAT. Dragging left in the viewport now stretches the wall left,
#   which is what the drawing shows and what the hand expects.
#
# HOW THE FACE IS CHOSEN FROM THE EDGE:
# - Every face the edge borders is scored by its SCREEN FACTOR: how much of its
#   normal lies in the plane of the screen, which is sqrt(1 - (n . camera)^2).
#   1.0 is a face perfectly edge-on to the camera (invisible, fully draggable);
#   0.0 is a face staring back at the camera (fully visible, undraggable).
# - The highest score wins, so the tool always takes the face you CANNOT see in
#   preference to the one you can. Ties inside a narrow band go to the larger
#   face, which keeps an isometric parallel view deterministic rather than
#   flip-flopping between two equally-angled candidates.
#
# THE DIRECT FACE PATH IS STILL THERE:
# - Parallel projection is not only used for elevations — isometric parallel
#   views are parallel too, and in those a face is perfectly grabbable. So when
#   no edge is under the cursor the tool falls back to the ordinary face grab,
#   but only if that face is oblique enough to be dragged meaningfully. A face
#   pointing at the camera is refused with a line telling the user to hover an
#   edge instead, rather than being silently accepted and behaving badly.
#
# CAMERA SWITCHING IS AUTOMATIC:
# - There is one Deep Push Pull command and one shortcut. Whichever activates
#   it asks the camera first, and while a tool is running an idle mouse move
#   re-checks: change to a 2D scene tab and the 2D variant takes over on the
#   next move; orbit back into perspective and the 3D one comes back. Handover
#   never happens mid-drag.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative 'Na__InsertPrimatives__DrawnPushPullTool__'
require_relative 'Na__InsertPrimatives__DrawnPushPull2d__Pick__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Screen Geometry Constants
    # -----------------------------------------------------------------------------

    # The floor for anything to be draggable at all. Below this a face's normal
    # is so nearly pointed at the camera that a whole viewport of mouse travel
    # buys almost no push, and the distance jumps wildly per pixel.
    NA_PP2D_MIN_SCREEN_FACTOR = 0.2588                                        # <-- sin 15 degrees

    # The direct-face fallback is deliberately stricter than the floor: if the
    # face is anywhere near face-on, the edge path is what the user meant.
    NA_PP2D_FACE_MIN_SCREEN   = 0.5000                                        # <-- sin 30 degrees

    # Two candidate faces scoring within this of each other are a tie, and are
    # separated by area instead. Without it an isometric parallel view picks
    # whichever of two 45-degree faces happened to round higher this frame.
    NA_PP2D_TIE_BAND          = 0.0200

    NA_PP2D_EDGE_WIDTH        = 5
    NA_PP2D_HOVER_EDGE        = Sketchup::Color.new(  0, 110, 235, 235)
    NA_PP2D_TARGET_LINE       = Sketchup::Color.new(  0, 170, 255, 200)
    NA_PP2D_SWEEP_FILL        = Sketchup::Color.new(255, 150,  30,  70)
    NA_PP2D_SWEEP_BORDER      = Sketchup::Color.new(226, 118,   0, 235)
    NA_PP2D_LABEL_PAD_PX      = 18.0                                          # <-- Clear space between a label block and what it labels

    # endregion -------------------------------------------------------------------


    # @delegate: Na__InsertPrimatives__DrawnPushPull2d__Pick__.rb

    # -----------------------------------------------------------------------------
    # REGION | Parallel Camera Push Pull Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Push/Pull Through an Edge, for Parallel Projection Work
    # ------------------------------------------------------------
    class DrawnPushPull2dTool < DrawnPushPullTool

        # FUNCTION | Forget the Grabbed Face and the Edge It Came From
        # ------------------------------------------------------------
        def na_drawn__clear_target
            super
            @na_pp2d_reason     = nil                                         # <-- :edge or :face, which path found the target
            @na_pp2d_edge_world = nil                                         # <-- The grabbed edge in world space, or nil
            @na_pp2d_refusal    = nil                                         # <-- Why the cursor is offering nothing
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Push/Pull 2D'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # Deliberately the SAME key as the 3D tool. To the user this is one tool
        # that adapts, so the popup must highlight one button either way.
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_push_pull
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'PARALLEL CAMERA MODE — the camera is 2D, so the pick is inverted',
                'Hover an EDGE you can see: the wall standing behind it is what moves',
                'Click to grab, drag across the screen, click to place',
                'Orbit into perspective and the 3D face version takes back over on its own',
                "Distance snaps to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid — hold CTRL for vertex snapping",
                'ARROWS lock the measured axis, TAB toggles QUAD mode',
                'With QUADS on, dragging INWARDS cuts an inset edge loop instead of shortening',
                'VCB: 300 | +50 | -25   (the typed distance pins and places)'
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Describe What Is Grabbed Rather Than a Drawing Plane
        # ------------------------------------------------------------
        def na_drawn__plane_description
            return 'Parallel camera — hover an edge' unless @na_pp_target

            "In #{Na__InsertPrimatives.Na__DeepPick__PathLabel(@na_pp_target)}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Target Selection — Edge First, Face Second
        # -----------------------------------------------------------------------------
        #
        # NOTE ON THE CAMERA HANDOVER: there is deliberately no onMouseMove here.
        # The inherited one already runs the camera check, and because that check
        # compares with instance_of? rather than is_a? it reads this subclass as
        # a distinct tool and hands back to the 3D one the moment the camera goes
        # perspective. Overriding it again would only ask the camera twice per
        # mouse move and give the same logic two places to drift apart in.
        # -----------------------------------------------------------------------------

        # FUNCTION | Track Whatever the Cursor Is Offering
        # ------------------------------------------------------------
        def na_drawn__hover_face(view, x, y)
            resolved = Na__InsertPrimatives.Na__PushPull2d__ResolveTargetAt(view, x, y)

            if resolved.nil? || resolved[:reason] == :none
                refusal = resolved ? resolved[:refusal] : nil
                na_drawn__clear_target
                @na_pp2d_refusal = refusal
                return false
            end

            na_drawn__adopt_2d_resolution(resolved)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Store a Resolution and Cache Its Face Geometry
        # ------------------------------------------------------------
        # The edge is recorded on its own account rather than being derived back
        # out of the face, because several edges of the same wall resolve to the
        # SAME face — the four sides of a wall end all border it. adopt_target
        # rightly skips its work when the face has not changed, so an edge left
        # to ride along with it would stick to whichever one was hovered first.
        # ------------------------------------------------------------
        def na_drawn__adopt_2d_resolution(resolved)
            @na_pp2d_reason     = resolved[:reason]
            @na_pp2d_edge_world = resolved[:edge_world]
            @na_pp2d_refusal    = nil

            na_drawn__adopt_target(resolved[:face_target])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Hold of the Wall Behind the Edge Under the Cursor
        # ------------------------------------------------------------
        def na_drawn__grab_face(view, x, y)
            resolved = Na__InsertPrimatives.Na__PushPull2d__ResolveTargetAt(view, x, y)

            if resolved.nil? || resolved[:reason] == :none
                UI.beep
                na_drawn__trace('grab refused — nothing pushable under the cursor')
                Sketchup::set_status_text(
                    (resolved && resolved[:refusal]) || 'Nothing pushable under the cursor',
                    SB_PROMPT
                )
                return false
            end

            target = resolved[:face_target]

            if target[:locked]
                UI.beep
                Sketchup::set_status_text('That wall is inside a locked group or component', SB_PROMPT)
                return false
            end

            na_drawn__adopt_2d_resolution(resolved)

            @na_ip.pick(view, x, y)
            @na_point_a = na_drawn__2d_anchor_point(resolved, view, x, y)
            return false unless @na_point_a

            @na_ip_origin.copy!(@na_ip)
            na_drawn__clear_locks
            @na_state  = :picking_depth
            @na_size_d = 0.0
            @na_sign_d = 1.0

            @na_drag_press_active = true                                      # <-- Arms press-drag-release
            @na_press_x           = @na_last_mouse_x
            @na_press_y           = @na_last_mouse_y

            na_drawn__warn_if_shared(target)
            na_drawn__trace("wall grabbed via #{@na_pp2d_reason}")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where the Drag Is Measured From
        # ------------------------------------------------------------
        # On the edge path the anchor is the point on the EDGE under the cursor,
        # not an inferred point: the edge is the thing the user aimed at, it is
        # dead-on the wall being moved, and it keeps the preview's swept quad
        # starting exactly where the line is drawn. The face path falls back to
        # the InputPoint, exactly as the 3D tool does.
        # ------------------------------------------------------------
        def na_drawn__2d_anchor_point(resolved, view, x, y)
            world = resolved[:edge_world]

            if world && world.length == 2
                direction = world[1] - world[0]

                if direction.length > 0
                    begin
                        on_edge = Geom.closest_points([world[0], direction.normalize], view.pickray(x, y))
                        return on_edge[0] if on_edge && on_edge[0]
                    rescue StandardError
                        nil
                    end
                end

                return Geom::Point3d.new(
                    (world[0].x.to_f + world[1].x.to_f) * 0.5,
                    (world[0].y.to_f + world[1].y.to_f) * 0.5,
                    (world[0].z.to_f + world[1].z.to_f) * 0.5
                )
            end

            target = resolved[:face_target]
            @na_ip.position ||
                Na__InsertPrimatives.Na__DeepPick__WorldOuterLoop(target[:face], target[:transformation]).first
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Drag Measurement Under a Parallel Camera
        # -----------------------------------------------------------------------------

        # FUNCTION | Project the Pick Ray onto the Push Direction
        # ------------------------------------------------------------
        # The inherited version discards a solution that lands behind the pick
        # ray's origin. That guard exists for PERSPECTIVE: an axis seen nearly
        # end-on hands back a point kilometres behind the eye, and using it
        # flips the drag inside out.
        #
        # Under a parallel camera the guard is not just unnecessary, it is
        # harmful. Every pixel gets its own ray origin sitting on the camera's
        # near plane, and where that plane falls relative to the model is
        # SketchUp's business, not ours — so a perfectly good solve on the wall
        # in front of the user can test as "behind" and be thrown away. The
        # symptom is a drag that silently freezes on the last good distance.
        #
        # The degeneracy the guard protects against cannot arise here either:
        # this tool only ever grabs a direction that lies across the screen, so
        # the push line and the pick ray are close to perpendicular, which is
        # the best-conditioned case the solve has. A direction that is not
        # draggable is refused at the pick instead, before it gets this far.
        # ------------------------------------------------------------
        def na_drawn__depth_point_from_ray(view, x, y)
            return super unless Na__InsertPrimatives.Na__PushPull2d__ParallelCamera?(view)

            direction = na_drawn__push_direction
            return nil unless direction && @na_point_a

            ray     = view.pickray(x, y)
            closest = Geom.closest_points([@na_point_a, direction], ray)
            return nil unless closest && closest[0]

            closest[0]
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Draggable the Current Push Direction Is on Screen
        # ------------------------------------------------------------
        def na_drawn__2d_drag_factor
            direction = na_drawn__push_direction
            return 0.0 unless direction

            view       = Sketchup.active_model ? Sketchup.active_model.active_view : nil
            camera_dir = Na__InsertPrimatives.Na__PushPull2d__CameraDirection(view)
            return 1.0 unless camera_dir

            Na__InsertPrimatives.Na__PushPull2d__ScreenFactor(direction, camera_dir)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arrow Keys Lock the Measured Axis, Screen Permitting
        # ------------------------------------------------------------
        # Two separate refusals now. The inherited one still applies — a face
        # edge-on to the locked axis cannot travel along it whatever the camera
        # is doing. On top of it, an axis that runs INTO the screen cannot be
        # dragged in a parallel view at all: the mouse has no way to express
        # travel along it, so the lock would leave the tool frozen at zero.
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            previous      = @na_axis_lock
            @na_axis_lock = (@na_axis_lock == axis) ? nil : axis

            if @na_axis_lock && @na_pp_target && !na_drawn__axis_lock_usable?
                @na_axis_lock = previous
                UI.beep
                Sketchup::set_status_text(
                    "This wall is edge-on to #{NA_DRAWN_AXIS_LABELS[axis]} — it cannot travel along it",
                    SB_PROMPT
                )
                return false
            end

            if @na_axis_lock && na_drawn__2d_drag_factor < NA_PP2D_MIN_SCREEN_FACTOR
                @na_axis_lock = previous
                UI.beep
                Sketchup::set_status_text(
                    "#{NA_DRAWN_AXIS_LABELS[axis]} runs into the screen in this view — orbit or pick another axis",
                    SB_PROMPT
                )
                return false
            end

            na_drawn__after_axis_lock_changed(view)
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview — Drawn for a Camera That Cannot See the Target
        # -----------------------------------------------------------------------------

        # FUNCTION | Points the Preview Occupies, for the Draw Extents
        # ------------------------------------------------------------
        def na_drawn__preview_points
            points = super
            return points unless @na_pp2d_edge_world

            points = points + @na_pp2d_edge_world

            offset = na_drawn__push_offset_vector
            return points unless offset && @na_state == :picking_depth

            points + @na_pp2d_edge_world.map { |point| point.offset(offset) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Highlight the Edge and Say Which Wall It Will Move
        # ------------------------------------------------------------
        # The target face is edge-on, so shading it would paint nothing. What is
        # drawn instead is the line the user aimed at, the target's outline (a
        # line too, but a longer one — it shows how much wall is coming), and an
        # arrow along the push direction so the direction of travel is readable
        # before a single pixel of drag.
        # ------------------------------------------------------------
        def na_drawn__draw_hover(view)
            return unless @na_pp_target

            unless @na_pp_loop.nil? || @na_pp_loop.empty?
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, @na_pp_triangles, NA_PP_HOVER_FILL)
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, @na_pp_loop, NA_PP2D_TARGET_LINE, 2)
            end

            anchor = na_drawn__2d_label_anchor
            return unless anchor

            if @na_pp2d_edge_world
                edge = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(@na_pp2d_edge_world)
                view.line_stipple  = ''
                view.line_width    = NA_PP2D_EDGE_WIDTH
                view.drawing_color = NA_PP2D_HOVER_EDGE
                view.draw_line(edge[0], edge[1])
                view.line_width    = 2
            end

            na_drawn__draw_direction_arrow(view, anchor, na_drawn__travel_direction)

            na_drawn__draw_label_clear_of(
                view, anchor, na_drawn__travel_direction, na_drawn__2d_hover_label_lines
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Centre a Label on a Point, Pushed Clear of a Direction
        # ------------------------------------------------------------
        # The default world label hangs off its anchor up and to the right, which
        # in this tool lands it straight on top of the direction arrow and reads
        # as though it belongs to nothing. Here it is centred on the anchor and
        # then pushed to the side OPPOSITE the arrow, measured in screen pixels:
        # arrow up puts the text below the edge, arrow left puts it to the right
        # of it, and either way the whole block clears the anchor by the padding
        # because half the block's own size along that direction is added to the
        # push. A horizontal edge with a vertical arrow — the common case — comes
        # out centred on the line and sitting just under it.
        # ------------------------------------------------------------
        def na_drawn__draw_label_clear_of(view, anchor, avoid, lines, color = nil)
            return unless anchor && lines

            screen         = view.screen_coords(
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(anchor)
            )
            away_x, away_y = na_drawn__screen_direction_away_from(view, anchor, avoid)
            width, height  = Na__InsertPrimatives.Na__DrawnPreview__TextBlockSize(lines)

            push = NA_PP2D_LABEL_PAD_PX +
                   (away_x.abs * width  * 0.5) +
                   (away_y.abs * height * 0.5)

            Na__InsertPrimatives.Na__DrawnPreview__DrawCentredScreenText(
                view,
                screen.x.to_f + (away_x * push),
                screen.y.to_f + (away_y * push),
                lines, color
            )
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Unit Screen Vector Pointing Away From a World Direction
        # Straight down is the fallback, for a direction with no side to be away
        # from — it cannot happen while a target is grabbed, since an undraggable
        # direction is refused at the pick, but a label must never be the thing
        # that raises in a draw pass.
        # ------------------------------------------------------------
        def na_drawn__screen_direction_away_from(view, anchor, direction)
            return [0.0, 1.0] unless direction

            anchor    = Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(anchor)
            direction = Na__InsertPrimatives.Na__DrawnPreview__ToDrawVector(direction)

            reach  = view.pixels_to_model(NA_DRAWN_ARROW_PIXELS, anchor)
            here   = view.screen_coords(anchor)
            there  = view.screen_coords(anchor.offset(direction, reach))

            away_x = here.x.to_f - there.x.to_f
            away_y = here.y.to_f - there.y.to_f
            length = Math.sqrt((away_x * away_x) + (away_y * away_y))
            return [0.0, 1.0] if length < 1.0

            [away_x / length, away_y / length]
        rescue StandardError
            [0.0, 1.0]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Lines Shown Beside the Hovered Edge
        # ------------------------------------------------------------
        def na_drawn__2d_hover_label_lines
            path = Na__InsertPrimatives.Na__DeepPick__PathLabel(@na_pp_target)

            lines =
                if @na_pp2d_reason == :edge && @na_pp2d_edge_world
                    length_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(
                        @na_pp2d_edge_world[0].distance(@na_pp2d_edge_world[1])
                    ).abs
                    ["#{length_mm} mm edge", "pulls the #{@na_pp_area} m2 wall behind it", path]
                else
                    ["#{@na_pp_area} m2 face", path]
                end

            if na_drawn__slope_mode?
                lines << "SHIFT SLOPE — #{Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope)}"
            elsif @na_pp_slope
                lines << "SHIFT — follow the #{Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope)} neighbour"
            end

            lines
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where a Hover Label and the Arrow Should Sit
        # ------------------------------------------------------------
        def na_drawn__2d_label_anchor
            if @na_pp2d_edge_world
                return Geom::Point3d.new(
                    (@na_pp2d_edge_world[0].x.to_f + @na_pp2d_edge_world[1].x.to_f) * 0.5,
                    (@na_pp2d_edge_world[0].y.to_f + @na_pp2d_edge_world[1].y.to_f) * 0.5,
                    (@na_pp2d_edge_world[0].z.to_f + @na_pp2d_edge_world[1].z.to_f) * 0.5
                )
            end

            return nil if @na_pp_loop.nil? || @na_pp_loop.empty?
            @na_pp_loop.first
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Arrow Saying Which Way This Wall Will Go
        # The arrow itself now lives in the preview graphics module, because the
        # 3D tool draws the same one during its push. This stays as the single
        # place that decides WHAT this tool points at — the face normal, which
        # before a drag begins is the only travel direction there is to show.
        # ------------------------------------------------------------
        def na_drawn__draw_direction_arrow(view, origin, direction)
            Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(view, origin, direction)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Preview the Wall at Its Pulled Position
        # ------------------------------------------------------------
        # The swept quad is the whole point of this preview. In an elevation the
        # grabbed edge sweeping along the push direction traces exactly the strip
        # of new wall the push is about to add, so the user sees the result as an
        # area on screen rather than as a number in the status bar.
        # ------------------------------------------------------------
        def na_drawn__draw_push_preview(view)
            offset = na_drawn__push_offset_vector
            live   = offset && Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)

            if @na_pp2d_edge_world
                edge = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(@na_pp2d_edge_world)
                view.line_stipple  = ''
                view.line_width    = NA_PP2D_EDGE_WIDTH
                view.drawing_color = na_drawn__quad_mode? ? NA_PP_QUAD_BORDER : NA_PP2D_HOVER_EDGE
                view.draw_line(edge[0], edge[1])
                view.line_width    = 2
            end

            unless @na_pp_loop.nil? || @na_pp_loop.empty?
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(
                    view, @na_pp_loop,
                    na_drawn__quad_mode? ? NA_PP_QUAD_BORDER : NA_PP2D_TARGET_LINE,
                    na_drawn__quad_mode? ? 3 : 1
                )
            end

            unless live
                na_drawn__draw_direction_arrow(view, na_drawn__2d_label_anchor, na_drawn__travel_direction)
                return
            end

            # On a loop cut the strip is still exactly the right thing to shade —
            # it is the nib the new line marks off — but the line itself is the
            # only geometry being created, so it takes the quad colour and the
            # sweep border steps back to a thin edge.
            cutting = na_drawn__loop_cut_mode?
            border  = cutting ? NA_PP_QUAD_BORDER : NA_PP2D_SWEEP_BORDER

            na_drawn__draw_sweep_quad(view, offset)

            return if @na_pp_loop.nil? || @na_pp_loop.empty?
            moved_loop = @na_pp_loop.map { |point| point.offset(offset) }

            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, moved_loop, border, cutting ? 3 : 2)

            if @na_pp2d_edge_world && cutting
                moved_edge = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(
                    [@na_pp2d_edge_world[0].offset(offset), @na_pp2d_edge_world[1].offset(offset)]
                )
                view.line_stipple  = ''
                view.line_width    = NA_PP2D_EDGE_WIDTH
                view.drawing_color = NA_PP_QUAD_BORDER
                view.draw_line(moved_edge[0], moved_edge[1])
                view.line_width    = 2
            end

            # Drawn here rather than through the preview module, so the pair of
            # loops has to be converted to draw space by hand.
            side_from = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(@na_pp_loop)
            side_to   = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(moved_loop)

            side_from.each_with_index do |point, index|
                view.drawing_color = border
                view.line_width    = 1
                view.draw_line(point, side_to[index])
            end

            na_drawn__draw_distance_label(view, moved_loop)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Label the Pull on the Strip It Is Adding
        # ------------------------------------------------------------
        # The inherited version hangs its label off `@na_pp_loop.first` — an
        # arbitrary corner of the target face. That face is edge-on here, so the
        # label lands at one end of a line, nowhere near the thing being
        # measured. It goes in the middle of the swept quad instead, which IS
        # what the number describes, and there is no arrow to dodge once a drag
        # is running. Falls back to the inherited label on the direct-face path,
        # where there is no swept quad to centre on.
        # ------------------------------------------------------------
        def na_drawn__draw_distance_label(view, moved_loop)
            return super unless @na_pp2d_edge_world

            offset    = na_drawn__push_offset_vector
            start_mid = na_drawn__2d_label_anchor
            return super unless offset && start_mid

            moved_mid = start_mid.offset(offset)
            centre    = Geom::Point3d.new(
                (start_mid.x.to_f + moved_mid.x.to_f) * 0.5,
                (start_mid.y.to_f + moved_mid.y.to_f) * 0.5,
                (start_mid.z.to_f + moved_mid.z.to_f) * 0.5
            )

            locked = na_drawn__locked?(:d)
            screen = view.screen_coords(
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(centre)
            )

            Na__InsertPrimatives.Na__DrawnPreview__DrawCentredScreenText(
                view, screen.x, screen.y,
                na_drawn__2d_distance_label_lines,
                @na_axis_lock ? Na__InsertPrimatives.Na__DrawnPreview__AxisColor(@na_axis_lock) :
                                Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(locked)
            )
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Lines Shown on the Swept Strip
        # ------------------------------------------------------------
        def na_drawn__2d_distance_label_lines
            distance = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
            shown    = na_drawn__locked?(:d) ? "[#{distance}]" : distance.to_s
            quads    = na_drawn__quad_mode? ? '  (quads)' : ''

            lines =
                if na_drawn__loop_cut_mode?
                    ["Loop cut #{shown} mm inset"]
                else
                    ["Pull #{shown} mm#{quads}"]
                end

            if @na_axis_lock
                along = Na__InsertPrimatives.Na__DrawnFormat__Mm(na_drawn__world_travel_distance).abs
                lines << "along #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]} · #{along} mm on the face normal"
            else
                lines << "#{@na_pp_area} m2 wall"
            end

            lines
        end
        # ---------------------------------------------------------------

        # FUNCTION | Shade the Strip of Wall the Push Is About to Add
        # ------------------------------------------------------------
        def na_drawn__draw_sweep_quad(view, offset)
            return unless @na_pp2d_edge_world

            near_a = @na_pp2d_edge_world[0]
            near_b = @na_pp2d_edge_world[1]

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view,
                [near_a, near_b, near_b.offset(offset), near_a.offset(offset)],
                NA_PP2D_SWEEP_FILL,
                NA_PP2D_SWEEP_BORDER
            )
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Bar and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            quads = na_drawn__quad_mode? ? ' QUADS' : ''
            slope = na_drawn__slope_hint

            if @na_state == :picking_depth
                distance = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
                text     = na_drawn__locked?(:d) ? "[#{distance}]" : distance.to_s
                return "Loop cut #{text} mm inset — release or click to cut#{slope}" if na_drawn__loop_cut_mode?

                verb = na_drawn__slope_mode? ? 'Slope' : 'Pull'
                return "#{verb}#{quads} #{text} mm — release or click to place#{slope}"
            end

            if @na_pp_target
                focus = na_drawn__focus_hint
                return "Edge grabs the #{@na_pp_area} m2 wall behind it — click to pull#{quads}#{slope}#{focus}" if @na_pp2d_reason == :edge
                return "Face #{@na_pp_area} m2 — click to grab it#{quads}#{slope}#{focus}"
            end

            return "#{@na_pp2d_refusal}#{quads}" if @na_pp2d_refusal
            "Hover an edge — the wall standing behind it is what moves#{quads}#{slope}#{na_drawn__focus_hint}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return [na_drawn__slope_mode? ? 'Slope distance' : 'Pull distance', ''] if @na_state != :picking_depth

            [na_drawn__slope_mode? ? 'Slope distance' : 'Pull distance', na_drawn__format_sizes([@na_size_d])]
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Distance Pins and Places
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            unless @na_state == :picking_depth
                UI.beep
                Sketchup::set_status_text('Grab an edge before typing a distance', SB_PROMPT)
                return false
            end

            super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPull2dTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Points
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the 2D Variant Explicitly (Testing / Console Entry)
    # The normal route is the camera-aware activator — this exists so the
    # variant can be forced from the Ruby Console when checking behaviour.
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepPushPull2d
        model = Sketchup.active_model
        return nil unless model

        tool = Na__InsertPrimatives::DrawnPushPull2dTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the 3D Variant Explicitly (Testing / Console Entry)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepPushPull3d
        model = Sketchup.active_model
        return nil unless model

        tool = Na__InsertPrimatives::DrawnPushPullTool.new
        model.select_tool(tool)
        tool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL 2D TOOL MODULE
# =============================================================================
