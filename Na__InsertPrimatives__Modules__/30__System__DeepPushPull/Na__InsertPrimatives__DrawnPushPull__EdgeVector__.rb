# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL ALONG AN EDGE (SHIFT+CLICK)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__EdgeVector__.rb
# NAMESPACE  : Na__InsertPrimatives / Na__InsertPrimatives::DrawnPushPullEdgeVector
# AUTHOR     : Noble Architecture
# PURPOSE    : Vector Push Pull: nominate any edge and the face travels along
#              that edge's line instead of along its own normal
# CREATED    : 2026
#
# DESCRIPTION:
# - A plain push carries a face along its normal. On the angled end of a slab
#   that throws the end off at an angle, when what is wanted is the slab carried
#   on along one of its own edges.
# - Hold SHIFT and any edge under the cursor is offered, at any nesting depth,
#   drawn in SketchUp's magenta parallel-lock colour. Click it and the face
#   travels parallel to it: the walls come out as parallelograms, and the far
#   end lands as a pure translation of where it started. Deep Project's edge
#   lock, for the push tool.
# - It works in either order: nominate first and then grab a face, or grab a
#   face and nominate mid-drag. Either way the distance is measured along the
#   edge, the grid still snaps it, and a typed number is that many mm along it.
#
# ONE PUSH ONLY, at Adam's word (05-Nov-2026): the edge lets go after the push it
# steered, so the tool is back to normal without having to be told. Deep Project's
# edge stays locked; this tool is reached for too often to be left in a mode. Until
# that push it waits, drawn the whole time: a cancelled drag, a refused push, a ring,
# or a face it stands down on do not use it up. BKSP releases it sooner, or
# SHIFT+click the same edge again.
#
# THE SIGN IS THE FACE'S:
# - An edge has no direction of its own, so it is turned to the face's outward
#   side, which keeps + meaning out and - meaning in, as everywhere in this tool
#   (loop cuts and the retype's minus both rely on that). The drag can go either
#   way along it.
# - An edge lying in the face cannot carry it anywhere. It is refused at the
#   click, and a lock already on stands down on such a face and says so.
#
# NOT WHAT SLOPE DOES, THOUGH IT LOOKS THE SAME (measured 05-Nov-2026):
# - Slope's push-then-shear is safe because its direction always lies in the
#   faces the push welds to. A nominated edge's need not. pushpull welds its new
#   wall into any neighbour square to the face and deletes the line between
#   them, so shearing the far end then TILTS that whole neighbour: a box's flat
#   top rose 300 mm across its full length in the live probe, with no error.
# - So the start loop is put back as edges BEFORE the shear, which un-welds them:
#   the neighbours stay exactly where they were and only the new walls lean. Any
#   wall that lands flush with its neighbour (the top of the slab, when the edge
#   runs along it) has its seam healed, so that face simply gets longer.
# - INTO the solid there is no such rescue: the push has cut those neighbours
#   back and the start loop is left in mid-air. Measured, a tilted box and a slab
#   with one side out of line both come out broken, not merely tilted. So going
#   in is allowed only in the two cases that hold up: every face round it contains
#   the edge (the solid simply shortens) or none is square to it (a panel on a
#   flat face: a leaning pocket). Anything else is refused before it is touched,
#   with the reason on the card. SHIFT+ALT Follow is the tool for shortening those.
#
# COORDINATES (the Coordinate Rule in the global notes):
# - The nominated edge is read once, through the pick's transformation, which
#   maps a leaf into the active context, and that is world. Its direction is then
#   a plain world vector and needs no further conversion: the tool's existing
#   offset maths (na_drawn__local_offset_vector, and re-splitting once a context
#   is entered) carries it from there, exactly as it carries a slope.
# - The points are kept for drawing and frozen with the direction: what was
#   nominated is the line, and it may be moved or deleted by anything done before
#   the push it is waiting for.
#
# 3D ONLY. In a parallel view the 2D variant's SHIFT is its own, and it inherits
# all of this switched off through na_ev__supported?.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Pick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'
require_relative 'Na__InsertPrimatives__DrawnPushPull__QuadRing__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Edge Vector Constants
    # -----------------------------------------------------------------------------

    NA_EDGE_VECTOR_COLOUR = Sketchup::Color.new(225, 0, 225, 255)             # <-- SketchUp's own parallel lock, as Deep Project draws its edge

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Geometry
    # -----------------------------------------------------------------------------

    # FUNCTION | An Edge's Line, Turned to a Face's Outward Side, or nil
    # ------------------------------------------------------------
    # nil when the line is within 5 degrees of lying in the face: the same limit
    # the slope and the arrow keys use, because pushpull would have almost nothing
    # to extrude along and the shear would be doing all the work.
    # ------------------------------------------------------------
    def self.Na__EdgeVector__DirectionFor(direction, normal)
        return nil unless direction && normal

        along = direction.dot(normal).to_f
        return nil if along.abs < NA_SLOPE_PUSH_MIN_FORWARD

        along < 0.0 ? direction.reverse : direction
    end
    # ---------------------------------------------------------------

    # FUNCTION | Would Going In Along This Line Break the Solid?
    # ------------------------------------------------------------
    # Fine when every face touching this one contains the line, because the tool
    # then just carries the face along it (the stretch route). Otherwise a
    # neighbour square to the face is the trouble: pushpull cuts it back going in,
    # so it stays attached to a far end about to be moved away from it. With none
    # of those, pushpull only makes walls and the result is a pocket. The vectors
    # are in the space the face reports, because that is where pushpull works.
    # ------------------------------------------------------------
    def self.Na__EdgeVector__InwardBlocked?(face, heading)
        return false unless face && face.valid? && heading && heading.length.to_f > 0.0
        return false if Na__InsertPrimatives.Na__SlopePush__CanStretch?(face, heading)

        normal = face.normal

        face.edges.any? do |edge|
            edge.faces.any? do |other|
                other != face && other.normal.dot(normal).abs <= NA_SLOPE_PUSH_IN_PLANE
            end
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Push, Un-Weld the Neighbours, Then Lean the Walls
    # ------------------------------------------------------------
    # distance and shear are what Na__SlopePush__SplitOffset gave: distance is the
    # pushpull scalar (definition units), along is that same share in the space
    # the face reports now, and shear is the sideways remainder in that space.
    # keep_ring leaves the start loop as quad lines; otherwise any seam that came
    # out flush is healed.
    #
    # Returns { :face, :stats, :healed }. Raises on anything it cannot do, and the
    # operation round it rolls back: a wall that leaned without its ring would
    # tilt a neighbour, so a ring that did not land stops the push instead.
    # ------------------------------------------------------------
    def self.Na__EdgeVector__PushAndShear(model, entities, face, distance, along, shear, interior, normal, keep_ring)
        outward = distance.to_f > 0.0
        loops   = outward ? Na__InsertPrimatives.Na__PushPull__CaptureLoops(face) : []
        corner  = face.outer_loop.vertices.first.position.clone

        face.pushpull(distance)

        travel = Geom::Vector3d.new(normal.x.to_f * along.to_f, normal.y.to_f * along.to_f, normal.z.to_f * along.to_f)
        moved  = Na__InsertPrimatives.Na__SlopePush__MovedFace(entities, face, interior, travel, normal) ||
                 Na__InsertPrimatives.Na__SlopePush__MovedFace(entities, face, interior, travel, nil)    # <-- A lone face pushed backwards: its far end faces the other way
        raise 'the pushed face could not be found again to move it along the edge' unless moved

        stats = nil
        unless loops.empty?
            build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, loops.first.first)
            stats = Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, loops, build)
            raise 'the start of the push could not be kept apart from the faces round it' if stats[:misplaced]
        end

        # The lean is what is left once pushpull has done its share, read off the
        # model rather than assumed: in a non-uniform scale pushpull's own share
        # is not square to the face, and the far end must still land exactly on
        # the line that was nominated.
        whole   = travel + shear
        expect  = corner.offset(travel)
        reached = moved.vertices.min_by { |vertex| vertex.position.distance(expect) }.position - corner

        unless Na__InsertPrimatives.Na__SlopePush__ApplyShear(entities, moved, whole - reached)
            raise 'the pushed face would not move along the edge — no vertex transform took'
        end

        # Moving vertices can re-make a face (measured on one with a hole), and the
        # seam heal reads the walls off it, so it is found again if it has gone.
        landed = moved
        unless landed.valid?
            landed = Na__InsertPrimatives.Na__SlopePush__MovedFace(entities, nil, interior, whole, normal) ||
                     Na__InsertPrimatives.Na__SlopePush__MovedFace(entities, nil, interior, whole, nil)
        end

        healed = keep_ring || landed.nil? ? 0 : Na__InsertPrimatives.Na__SlopePush__HealSeam(landed)

        { :face => landed, :stats => stats, :healed => healed }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Tool Side
    # -----------------------------------------------------------------------------

    module DrawnPushPullEdgeVector

        # -----------------------------------------------------------------------------
        # REGION | State
        # -----------------------------------------------------------------------------

        # FUNCTION | Nothing Nominated Yet
        # ------------------------------------------------------------
        def na_ev__init_state
            @na_ev_lock     = nil                                             # <-- The nominated edge: until the push it steers, or released
            @na_ev_hover    = nil                                             # <-- The edge SHIFT is offering under the cursor
            @na_ev_settling = nil                                             # <-- Where the mouse was when an edge was taken mid-drag
        end
        # ---------------------------------------------------------------

        # FUNCTION | 3D Only
        # ------------------------------------------------------------
        def na_ev__supported?
            !(defined?(Na__InsertPrimatives::DrawnPushPull2dTool) && is_a?(Na__InsertPrimatives::DrawnPushPull2dTool))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is an Edge on Offer Under the Cursor?
        # ------------------------------------------------------------
        def na_ev__hovering?
            !@na_ev_hover.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does a Surface Mean the Lock Cannot Apply Here?
        # ------------------------------------------------------------
        # Every face of a surface moves along its own normal, so one line cannot
        # carry it: the same stand-down SHIFT slope and SHIFT+ALT follow make. A
        # replay is exempt because its record is one face, whatever is hovered.
        # ------------------------------------------------------------
        def na_ev__stands_down?
            return false if @na_revise_replaying
            return true if @na_pp_joint

            na_pps__active? && na_pps__units.any? { |unit| unit[:joint] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The World Direction This Face Travels Along, or nil
        # ------------------------------------------------------------
        def na_ev__direction
            lock = @na_ev_lock
            return nil unless lock && @na_pp_target
            return nil if na_ev__stands_down?

            Na__InsertPrimatives.Na__EdgeVector__DirectionFor(lock[:direction], @na_pp_target[:world_normal])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Lock Actually Steering This Face?
        # ------------------------------------------------------------
        def na_ev__live?
            !na_ev__direction.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Set Lock Outranks SHIFT+ALT, as It Does in Deep Project
        # It was set on purpose and stays set; the held keys are the lesser of the
        # two. Slope stands down the same way, in na_drawn__slope_mode?.
        # ------------------------------------------------------------
        def na_drawn__follow_requested?
            return false if na_ev__live?

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why This Live Push Cannot Be Placed, or nil
        # ------------------------------------------------------------
        # Only one case: travelling INTO the solid where the faces round it would
        # not hold up (see the module header). A loop cut moves nothing, so it has
        # its own say on whether the ring lands.
        # ------------------------------------------------------------
        def na_ev__problem
            return nil unless na_ev__live?
            return nil unless na_drawn__world_travel_distance < 0.0
            return nil if na_drawn__loop_cut_mode?

            target  = @na_pp_target
            heading = na_drawn__local_offset_vector(target)
            return nil unless Na__InsertPrimatives.Na__EdgeVector__InwardBlocked?(target[:face], heading)

            'going in along this edge would break the faces round it — pull it out, nominate an edge lying in all of them, or use SHIFT+ALT'
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Nominating
        # -----------------------------------------------------------------------------

        # FUNCTION | Is SHIFT Asking for an Edge Right Now?
        # ------------------------------------------------------------
        # CTRL+SHIFT is the vertex-then-grid snap and SHIFT+ALT is follow, so
        # neither looks for an edge. A grabbed ring measures along its own run.
        # ------------------------------------------------------------
        def na_ev__wanted?
            return false unless @na_shift_held && !@na_ctrl_held && !@na_alt_held
            return false unless na_ev__supported?

            !na_qo__active?
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Picked Edge as a World Line
        # ------------------------------------------------------------
        def na_ev__candidate(picked)
            edge  = picked[:edge]
            xform = picked[:transformation]
            return nil unless edge && edge.valid?

            start  = edge.start.position.transform(xform)
            finish = edge.end.position.transform(xform)
            length = start.distance(finish).to_f
            return nil unless length > 0.0

            direction = (finish - start).normalize

            {
                :key       => [edge.entityID, xform.to_a],
                :points    => [start, finish],
                :direction => direction,
                :length    => length,
                :name      => Na__InsertPrimatives.Na__DeepPick__PathLabel(picked),
                :refusal   => na_ev__refusal(direction)
            }
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why This Edge Cannot Carry the Face in Hand, or nil
        # ------------------------------------------------------------
        # Refused only when it can carry none of them: with several faces
        # preselected, the ones it cannot carry stand down on their own. With
        # nothing in hand there is nothing to judge it against yet.
        # ------------------------------------------------------------
        def na_ev__refusal(direction)
            faces =
                if na_pps__active?                then @na_pps_targets
                elsif @na_state == :picking_depth then [@na_pp_target].compact
                else                                   []
                end
            return nil if faces.empty?

            usable = faces.any? do |target|
                Na__InsertPrimatives.Na__EdgeVector__DirectionFor(direction, target[:world_normal])
            end

            usable ? nil : 'runs along the face — it cannot carry it anywhere'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Offer the Edge Under the Cursor While SHIFT Is Down
        # ------------------------------------------------------------
        # Mid-drag this is the one pick the tool makes, and only because SHIFT
        # asked: with SHIFT up it costs nothing.
        # ------------------------------------------------------------
        def na_ev__track_hover(view, x, y)
            @na_ev_hover = nil
            return nil unless na_ev__wanted?

            picked       = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)
            @na_ev_hover = picked ? na_ev__candidate(picked) : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A SHIFT+Click: on an Edge It Nominates, Anywhere Else It Is Not Ours
        # ------------------------------------------------------------
        # Asked fresh at the click rather than trusting the last hover. Returns
        # true when the click was on an edge and has been used, so it neither
        # grabs a face nor places a push, whichever the edge's answer was. False
        # leaves SHIFT+click on a face meaning what it always has.
        # ------------------------------------------------------------
        def na_ev__try_click(view, x, y)
            return false unless na_ev__wanted?

            picked    = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)
            candidate = picked ? na_ev__candidate(picked) : nil
            return false unless candidate

            @na_drag_press_active = false
            @na_ev_hover          = candidate
            na_drawn__trace("edge clicked: #{candidate[:name]}")

            if @na_ev_lock && @na_ev_lock[:key] == candidate[:key]
                na_ev__release
                na_drawn__after_axis_lock_changed(view)
            elsif candidate[:refusal]
                UI.beep
                na_revise__notice("That edge #{candidate[:refusal]}")
            else
                na_ev__take(candidate, view)
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take an Edge
        # ------------------------------------------------------------
        # Mid-drag the cursor is sitting on the edge just clicked, which can be
        # anywhere, often behind the face. So the distance stays at nothing and
        # the sign stays outward until the mouse is moved on: typing 1000 straight
        # after the click means 1000 out, not 1000 towards wherever that edge was.
        # A locked axis the new line cannot travel along has nothing left to
        # measure, so it lets go rather than leaving the drag stuck at zero.
        # ------------------------------------------------------------
        def na_ev__take(candidate, view)
            @na_ev_lock = candidate

            if @na_state == :picking_depth
                @na_size_d      = 0.0
                @na_sign_d      = 1.0
                @na_ev_settling = [@na_last_mouse_x.to_f, @na_last_mouse_y.to_f]
            end

            @na_axis_lock = nil unless na_drawn__axis_lock_usable?
            na_drawn__after_axis_lock_changed(view)

            note = na_ev__stands_down? ? ' — this surface keeps to its own normals, SHIFT+TAB pushes one face' : ''
            push = @na_state == :picking_depth ? 'This push follows' : 'The next push follows'
            na_revise__notice("#{push} the edge in #{candidate[:name]}#{note} — BKSP releases it")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Let the Edge Go, Saying So; false When None Was Held
        # ------------------------------------------------------------
        def na_ev__release
            return false unless @na_ev_lock

            @na_ev_lock     = nil
            @na_ev_settling = nil
            na_revise__notice('Edge released — the face travels along its own normal again')
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Has the Mouse Stayed Put Since an Edge Was Taken Mid-Drag?
        # ------------------------------------------------------------
        def na_ev__settling?(x, y)
            mark = @na_ev_settling
            return false unless mark

            travelled = (x.to_f - mark[0]).abs + (y.to_f - mark[1]).abs
            return true if travelled < DrawnToolShared::NA_DRAWN_DRAG_MIN_PX && !@na_ctrl_held

            @na_ev_settling = nil
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Lock a Placed Push Was Made Under, Batch or Not
        # ------------------------------------------------------------
        def na_ev__record_lock(record)
            return record[:edge_lock] if record[:edge_lock]

            (record[:members] || []).map { |member| member[:edge_lock] }.compact.first
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Commit
        # -----------------------------------------------------------------------------

        # FUNCTION | Place a Push, and Let the Edge Go If It Steered It
        # ------------------------------------------------------------
        # Asked before the commit, which clears the face in hand. A surface's push
        # and a face it stands down on never read it, so it waits for one that does.
        # ------------------------------------------------------------
        def na_drawn__commit_push(view)
            steering = na_ev__live?
            placed   = super
            na_ev__spend if placed && steering
            placed
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Edge Has Done Its One Push
        # ------------------------------------------------------------
        # A retype's rebuild comes through here too and loses nothing: it wears the
        # line its record holds, and na_revise__wearing puts back whatever is
        # nominated by then, so a new edge taken in between is still waiting.
        # ------------------------------------------------------------
        def na_ev__spend
            @na_ev_lock     = nil
            @na_ev_settling = nil
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Push and Lean, Reporting Into the Commit's Own Variables
        # ------------------------------------------------------------
        def na_ev__execute(model, entities, face, distance, working_split, interior, normal, quads)
            result = Na__InsertPrimatives.Na__EdgeVector__PushAndShear(
                model, entities, face, distance, working_split[:distance], working_split[:shear],
                interior, normal, quads
            )

            @na_pp_quad_stats  = result[:stats] if quads
            @na_pp_seam_healed = result[:healed]
            na_drawn__trace('along an edge: pushed, start loop kept apart, walls leaned')
            result[:face]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Wording
        # -----------------------------------------------------------------------------

        # FUNCTION | How Far the Line Is Off This Face's Normal
        # ------------------------------------------------------------
        def na_ev__angle_label
            direction = na_ev__direction
            return '' unless direction

            "#{format('%.1f', Na__InsertPrimatives.Na__SlopePush__Degrees(direction.dot(@na_pp_target[:world_normal])))}° off normal"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why a Set Lock Is Not Steering This Face
        # ------------------------------------------------------------
        def na_ev__off_reason
            return 'a surface keeps to its own normals, SHIFT+TAB pushes one face' if na_ev__stands_down?

            'it runs along this face, so this face pushes along its normal'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Status Line While an Edge Is on Offer
        # ------------------------------------------------------------
        def na_ev__hover_status
            hover = @na_ev_hover
            return "That edge #{hover[:refusal]}" if hover[:refusal]
            return 'The locked edge — SHIFT+click or BKSP releases it' if @na_ev_lock && @na_ev_lock[:key] == hover[:key]

            "SHIFT+click — push along this edge (#{Na__InsertPrimatives.Na__DrawnFormat__Mm(hover[:length]).abs} mm, #{hover[:name]})"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Status Fragment While a Lock Is On
        # ------------------------------------------------------------
        def na_ev__status_hint
            return '' unless @na_ev_lock
            return ' — along the locked edge (BKSP releases it)' unless @na_pp_target
            return " — EDGE off here: #{na_ev__off_reason}" unless na_ev__live?

            problem = na_ev__problem
            return " — NOT PLACEABLE: #{problem}" if problem

            " — along the locked edge, #{na_ev__angle_label} (BKSP releases it)"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Line on the Hovered Face's Card
        # ------------------------------------------------------------
        def na_ev__face_note
            return nil unless @na_ev_lock
            return "EDGE off here — #{na_ev__off_reason}" unless na_ev__live?

            "ALONG THE EDGE — #{na_ev__angle_label}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Key Reminder at the End of the Status Line
        # ------------------------------------------------------------
        def na_ev__tab_hint
            return '' unless na_ev__supported?

            @na_ev_lock ? '  EDGE locked' : '  SHIFT+click edge: push along it'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | The Locked Edge, the Travel Along It, and the Edge on Offer
        # ------------------------------------------------------------
        def na_ev__draw(view)
            na_ev__draw_lock(view) if @na_ev_lock
            na_ev__draw_hover(view) if @na_ev_hover
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Heavy Line, an Arrow the Way It Pushes, and a Guide Mid-Drag
        # ------------------------------------------------------------
        def na_ev__draw_lock(view)
            start, finish = @na_ev_lock[:points]
            na_ev__draw_line(view, start, finish, NA_EDGE_VECTOR_COLOUR, 4, '')

            pointing = na_ev__direction
            return unless pointing

            middle = Geom::Point3d.linear_combination(0.5, start, 0.5, finish)
            Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(view, middle, pointing, NA_EDGE_VECTOR_COLOUR)

            return unless @na_state == :picking_depth && @na_point_a

            offset = na_drawn__push_offset_vector
            return unless offset && offset.length.to_f > 0.0

            na_ev__draw_line(view, @na_point_a, @na_point_a.offset(offset), NA_EDGE_VECTOR_COLOUR, 2, '_')
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Edge Under the Cursor: Magenta if It Will Do, Red if Not
        # ------------------------------------------------------------
        def na_ev__draw_hover(view)
            hover         = @na_ev_hover
            start, finish = hover[:points]
            refused       = !hover[:refusal].nil?
            locked        = @na_ev_lock && @na_ev_lock[:key] == hover[:key]

            na_ev__draw_line(view, start, finish, refused ? NA_DRAWN_REFUSED_BORDER_CLR : NA_EDGE_VECTOR_COLOUR, 3, '-')

            lines =
                if refused then ["That edge #{hover[:refusal]}"]
                elsif locked then ['The locked edge — SHIFT+click releases it']
                else ['SHIFT+click — push along this edge', "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(hover[:length]).abs} mm, #{hover[:name]}"]
                end

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, Geom::Point3d.linear_combination(0.5, start, 0.5, finish), lines,
                14, -26, refused ? NA_DRAWN_REFUSED_TEXT_COLOR : nil
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Line Between Two World Points
        # ------------------------------------------------------------
        def na_ev__draw_line(view, start, finish, colour, width, stipple)
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

        # GET EXTENTS | The Edge Can Be Anywhere in the Model, Off the Face's Bounds
        # ------------------------------------------------------------
        def getExtents
            bounds = super
            [@na_ev_lock, @na_ev_hover].compact.each do |edge|
                edge[:points].each { |point| bounds.add(point) }
            end
            bounds
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullEdgeVector module

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL ALONG AN EDGE
# =============================================================================
