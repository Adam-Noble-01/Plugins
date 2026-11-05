# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP PUSH PULL ALONG AN EDGE (SHIFT+CLICK)
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnPushPull__EdgeVector__.rb
# NAMESPACE  : Na__NobleDrawingTools / Na__NobleDrawingTools::DrawnPushPullEdgeVector
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
# HOLD SHIFT MID-DRAG FOR A SQUARE END (asked for 05-Nov-2026, from two sketches):
# - Without it the far end is a copy of the start, parallel to it. With SHIFT held
#   the far end comes out square to the edge, with the walls running into it at
#   90 degrees.
# - The plane goes through the corner that travels furthest, at the distance
#   dragged. That corner lands exactly where it would have anyway and every other
#   corner runs on along its own rail to meet the plane, which adds the wedge in
#   the sketches rather than cutting into the push. So pressing SHIFT never moves
#   the corner in front, and the number on the card is that corner's travel.
# - Every rail is parallel to the edge, so each wall stays flat however long its
#   rails are, and the end is flat because every corner lands on one plane.
# - Mid-drag along an edge SHIFT only ever means this, so a SHIFT+click there places
#   the push instead of looking for another edge: BKSP first to change edges. The
#   SHIFT that nominated the edge does not count until it has been let go, or a
#   push taken with SHIFT still down would square itself by accident.
# - A loop cut moves nothing and has no end to square, so it stands SHIFT down.
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
# - A square end is worked out in WORLD, because square is only true there: in a
#   non-uniformly scaled group a plane square to the line in world is not square to
#   it in the definition. Each corner goes out to world, onto the plane, and back
#   through the same transformation the Follow route uses.
#
# 3D ONLY. In a parallel view the 2D variant's SHIFT is its own, and it inherits
# all of this switched off through na_ev__supported?.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__Pick__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnSlopePush__'
require_relative 'Na__NobleDrawingTools__DrawnPushPull__QuadRing__'

module Na__NobleDrawingTools

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
        return false if Na__NobleDrawingTools.Na__SlopePush__CanStretch?(face, heading)

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

    # FUNCTION | How Far Along a Line a World Point Sits
    # ------------------------------------------------------------
    def self.Na__EdgeVector__LevelOf(point, direction)
        (point.x.to_f * direction.x.to_f) + (point.y.to_f * direction.y.to_f) + (point.z.to_f * direction.z.to_f)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Slide a World Point Along a Line Onto the Plane at a Level
    # ------------------------------------------------------------
    def self.Na__EdgeVector__OntoLevel(point, direction, level)
        Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(point, direction, level.to_f - Na__NobleDrawingTools.Na__EdgeVector__LevelOf(point, direction))
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Level a Square End Lands On, From Where the Corners Sit
    # ------------------------------------------------------------
    # The corner furthest along the way it is travelling leads, by the distance:
    # out, the one highest along the line; back, the one lowest.
    # ------------------------------------------------------------
    def self.Na__EdgeVector__SquareLevel(span, distance)
        (distance.to_f < 0.0 ? span[:min] : span[:max]) + distance.to_f
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read the Plane a Square End Lands On, Before Anything Moves
    # ------------------------------------------------------------
    # points are in the space the face reports; xform carries that space to world.
    # ------------------------------------------------------------
    def self.Na__EdgeVector__SquarePlan(points, direction, distance, xform)
        levels = points.map { |point| Na__NobleDrawingTools.Na__EdgeVector__LevelOf(point.transform(xform), direction) }

        {
            :direction => direction,
            :level     => Na__NobleDrawingTools.Na__EdgeVector__SquareLevel({ :min => levels.min, :max => levels.max }, distance),
            :xform     => xform,
            :inverse   => xform.inverse
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Where a Reported Point Lands on the Square End, Reported
    # ------------------------------------------------------------
    def self.Na__EdgeVector__SquareLand(point, plan)
        Na__NobleDrawingTools.Na__EdgeVector__OntoLevel(point.transform(plan[:xform]), plan[:direction], plan[:level]).transform(plan[:inverse])
    end
    # ---------------------------------------------------------------

    # FUNCTION | Move Vertices Onto the Square End, Each Along Its Own Rail
    # ------------------------------------------------------------
    # starts says where each vertex counts as starting from. Raises if a corner
    # misses, so the operation round it rolls back rather than leaving a skewed end.
    # ------------------------------------------------------------
    def self.Na__EdgeVector__SquareMove(entities, vertices, starts, plan)
        wanted  = starts.map { |point| Na__NobleDrawingTools.Na__EdgeVector__SquareLand(point, plan) }
        vectors = vertices.each_with_index.map { |vertex, index| wanted[index] - vertex.position }

        entities.transform_by_vectors(vertices, vectors)

        vertices.each_with_index do |vertex, index|
            next unless vertex.valid?
            next if vertex.position.distance(wanted[index]) < NA_FOLLOW_TOL

            raise 'a corner did not land on the square end'
        end

        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Face Round It Contains the Line: Just Carry Each Corner
    # ------------------------------------------------------------
    def self.Na__EdgeVector__SquareStretch(entities, face, plan)
        vertices = face.vertices
        Na__NobleDrawingTools.Na__EdgeVector__SquareMove(entities, vertices, vertices.map { |vertex| vertex.position.clone }, plan)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Finish a Square End From Where pushpull Left the Face
    # ------------------------------------------------------------
    # pushpull carried the whole face by one translation, so each vertex's start is
    # its position less that translation, read as the shift of the two middles. That
    # is measured for the same reason the lean is: in a non-uniform scale it is not
    # square to the face, and a nearest-vertex guess could take the wrong corner.
    # ------------------------------------------------------------
    def self.Na__EdgeVector__SquareAfterPush(entities, moved, starts, plan)
        vertices = moved.vertices
        raise 'the pushed face came back with a different outline' unless vertices.length == starts.length

        count  = vertices.length.to_f
        before = starts.inject([0.0, 0.0, 0.0]) { |sum, p| [sum[0] + p.x.to_f, sum[1] + p.y.to_f, sum[2] + p.z.to_f] }
        after  = vertices.inject([0.0, 0.0, 0.0]) { |sum, v| p = v.position; [sum[0] + p.x.to_f, sum[1] + p.y.to_f, sum[2] + p.z.to_f] }
        shift  = [(after[0] - before[0]) / count, (after[1] - before[1]) / count, (after[2] - before[2]) / count]

        origins = vertices.map do |vertex|
            p = vertex.position
            Geom::Point3d.new(p.x.to_f - shift[0], p.y.to_f - shift[1], p.z.to_f - shift[2])
        end

        Na__NobleDrawingTools.Na__EdgeVector__SquareMove(entities, vertices, origins, plan)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Push, Un-Weld the Neighbours, Then Lean the Walls
    # ------------------------------------------------------------
    # distance and shear are what Na__SlopePush__SplitOffset gave: distance is the
    # pushpull scalar (definition units), along is that same share in the space
    # the face reports now, and shear is the sideways remainder in that space.
    # keep_ring leaves the start loop as quad lines; otherwise any seam that came
    # out flush is healed. square is a plan for a square end, or nil for an end
    # parallel to the start.
    #
    # Returns { :face, :stats, :healed }. Raises on anything it cannot do, and the
    # operation round it rolls back: a wall that leaned without its ring would
    # tilt a neighbour, so a ring that did not land stops the push instead.
    # ------------------------------------------------------------
    def self.Na__EdgeVector__PushAndShear(model, entities, face, distance, along, shear, interior, normal, keep_ring, square = nil)
        outward = distance.to_f > 0.0
        loops   = outward ? Na__NobleDrawingTools.Na__PushPull__CaptureLoops(face) : []
        corner  = face.outer_loop.vertices.first.position.clone
        starts  = square ? face.vertices.map { |vertex| vertex.position.clone } : nil

        face.pushpull(distance)

        travel = Geom::Vector3d.new(normal.x.to_f * along.to_f, normal.y.to_f * along.to_f, normal.z.to_f * along.to_f)
        moved  = Na__NobleDrawingTools.Na__SlopePush__MovedFace(entities, face, interior, travel, normal) ||
                 Na__NobleDrawingTools.Na__SlopePush__MovedFace(entities, face, interior, travel, nil)   # <-- A lone face pushed backwards: its far end faces the other way
        raise 'the pushed face could not be found again to move it along the edge' unless moved

        stats = nil
        unless loops.empty?
            build = Na__NobleDrawingTools.Na__DeepPick__AddTransform(model, entities, loops.first.first)
            stats = Na__NobleDrawingTools.Na__PushPull__StitchQuadRing(entities, loops, build)
            raise 'the start of the push could not be kept apart from the faces round it' if stats[:misplaced]
        end

        # The lean is what is left once pushpull has done its share, read off the
        # model rather than assumed: in a non-uniform scale pushpull's own share
        # is not square to the face, and the far end must still land exactly on
        # the line that was nominated.
        if square
            whole = Na__NobleDrawingTools.Na__EdgeVector__SquareLand(interior, square) - interior
            Na__NobleDrawingTools.Na__EdgeVector__SquareAfterPush(entities, moved, starts, square)
        else
            whole   = travel + shear
            expect  = corner.offset(travel)
            reached = moved.vertices.min_by { |vertex| vertex.position.distance(expect) }.position - corner

            unless Na__NobleDrawingTools.Na__SlopePush__ApplyShear(entities, moved, whole - reached)
                raise 'the pushed face would not move along the edge — no vertex transform took'
            end
        end

        # Moving vertices can re-make a face (measured on one with a hole), and the
        # seam heal reads the walls off it, so it is found again if it has gone.
        landed = moved
        unless landed.valid?
            landed = Na__NobleDrawingTools.Na__SlopePush__MovedFace(entities, nil, interior, whole, normal) ||
                     Na__NobleDrawingTools.Na__SlopePush__MovedFace(entities, nil, interior, whole, nil)
        end

        healed = keep_ring || landed.nil? ? 0 : Na__NobleDrawingTools.Na__SlopePush__HealSeam(landed)

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
            @na_ev_nominating = false                                         # <-- The SHIFT that took the edge is still down
            @na_ev_span     = nil                                             # <-- How far along the line the face in hand reaches, kept between frames
        end
        # ---------------------------------------------------------------

        # FUNCTION | 3D Only
        # ------------------------------------------------------------
        def na_ev__supported?
            !(defined?(Na__NobleDrawingTools::DrawnPushPull2dTool) && is_a?(Na__NobleDrawingTools::DrawnPushPull2dTool))
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

            Na__NobleDrawingTools.Na__EdgeVector__DirectionFor(lock[:direction], @na_pp_target[:world_normal])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Lock Actually Steering This Face?
        # ------------------------------------------------------------
        def na_ev__live?
            !na_ev__direction.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Face Being Dragged Along the Edge Right Now?
        # ------------------------------------------------------------
        # Not a grabbed quad ring: that measures along its own run, and an edge left
        # waiting has no say in it until a face is taken.
        # ------------------------------------------------------------
        def na_ev__dragging?
            @na_state == :picking_depth && !na_qo__active? && na_ev__live?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is SHIFT Squaring the End of This Push?
        # ------------------------------------------------------------
        # A replay answers with what the push it is rebuilding was made with, not
        # with what is held now, exactly as the quad setting does.
        # ------------------------------------------------------------
        def na_ev__square?
            return false unless @na_ev_lock && na_ev__live?
            return false if na_drawn__loop_cut_mode?
            return @na_revise_replaying[:square] ? true : false if @na_revise_replaying

            na_ev__dragging? && @na_shift_held && !@na_ev_nominating ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far Along the Line the Face in Hand Reaches
        # ------------------------------------------------------------
        # Off the cached world loop, whose extremes are the face's: a hole is inside
        # it. Kept between frames because the preview asks for every point it moves.
        # ------------------------------------------------------------
        def na_ev__span
            points    = @na_pp_loop
            direction = na_ev__direction
            return nil if points.nil? || points.empty? || direction.nil?

            key = [points.object_id, direction.x.to_f, direction.y.to_f, direction.z.to_f]
            return @na_ev_span if @na_ev_span && @na_ev_span[:key] == key

            levels      = points.map { |point| Na__NobleDrawingTools.Na__EdgeVector__LevelOf(point, direction) }
            @na_ev_span = { :key => key, :direction => direction, :min => levels.min, :max => levels.max }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where a World Point of the Face Goes Under a Square End
        # ------------------------------------------------------------
        # The preview's one hook: the loop, the triangles and the rungs all come
        # through here, so they cannot disagree. The same plane the commit lands on.
        # ------------------------------------------------------------
        def na_drawn__move_world_point(point, offset)
            return super unless offset && na_ev__square?

            span = na_ev__span
            return super unless span

            level = Na__NobleDrawingTools.Na__EdgeVector__SquareLevel(span, na_drawn__world_travel_distance)
            Na__NobleDrawingTools.Na__EdgeVector__OntoLevel(point, span[:direction], level)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Commit's Plan for a Square End, or nil
        # ------------------------------------------------------------
        # Read in the space the face reports now. Once its context is entered that is
        # world and the identity carries it; not entered, the pick's transformation
        # does, as for Follow.
        # ------------------------------------------------------------
        def na_ev__square_plan(face, target, entered)
            return nil unless na_ev__square?

            xform = entered ? Geom::Transformation.new : target[:transformation]

            Na__NobleDrawingTools.Na__EdgeVector__SquarePlan(
                face.vertices.map { |vertex| vertex.position },
                na_ev__direction, na_drawn__world_travel_distance, xform
            )
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
            return nil unless Na__NobleDrawingTools.Na__EdgeVector__InwardBlocked?(target[:face], heading)

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
        # neither looks for an edge. A grabbed ring measures along its own run, and
        # mid-drag along an edge SHIFT squares the end instead.
        # ------------------------------------------------------------
        def na_ev__wanted?
            return false unless @na_shift_held && !@na_ctrl_held && !@na_alt_held
            return false unless na_ev__supported?
            return false if na_ev__dragging?

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
                :name      => Na__NobleDrawingTools.Na__DeepPick__PathLabel(picked),
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
                Na__NobleDrawingTools.Na__EdgeVector__DirectionFor(direction, target[:world_normal])
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
            @na_ev_hover      = nil
            @na_ev_nominating = false unless @na_shift_held                   # <-- Let go at last: the next SHIFT is free to square
            return nil unless na_ev__wanted?

            picked       = Na__NobleDrawingTools.Na__DeepPick__EdgeAt(view, x, y)
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

            picked    = Na__NobleDrawingTools.Na__DeepPick__EdgeAt(view, x, y)
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
            @na_ev_lock       = candidate
            @na_ev_nominating = true

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
        def na_ev__execute(model, entities, face, distance, working_split, interior, normal, quads, square)
            result = Na__NobleDrawingTools.Na__EdgeVector__PushAndShear(
                model, entities, face, distance, working_split[:distance], working_split[:shear],
                interior, normal, quads, square
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

            "#{format('%.1f', Na__NobleDrawingTools.Na__SlopePush__Degrees(direction.dot(@na_pp_target[:world_normal])))}° off normal"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why a Set Lock Is Not Steering This Face
        # ------------------------------------------------------------
        def na_ev__off_reason
            return 'a surface keeps to its own normals, SHIFT+TAB pushes one face' if na_ev__stands_down?

            'it runs along this face, so this face pushes along its normal'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What This Push Is Called on the Card and the Status Line
        # ------------------------------------------------------------
        def na_ev__verb
            na_ev__square? ? 'Square end' : 'Along edge'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Status Line While an Edge Is on Offer
        # ------------------------------------------------------------
        def na_ev__hover_status
            hover = @na_ev_hover
            return "That edge #{hover[:refusal]}" if hover[:refusal]
            return 'The locked edge — SHIFT+click or BKSP releases it' if @na_ev_lock && @na_ev_lock[:key] == hover[:key]

            "SHIFT+click — push along this edge (#{Na__NobleDrawingTools.Na__DrawnFormat__Mm(hover[:length]).abs} mm, #{hover[:name]})"
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
            return ' — end square to the edge, every corner on its own rail (SHIFT up: parallel to the start)' if na_ev__square?

            squares = na_ev__dragging? ? 'hold SHIFT to square the end, ' : ''
            " — along the locked edge, #{na_ev__angle_label} (#{squares}BKSP releases it)"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Line on the Hovered Face's Card
        # ------------------------------------------------------------
        def na_ev__face_note
            return nil unless @na_ev_lock
            return "EDGE off here — #{na_ev__off_reason}" unless na_ev__live?

            "ALONG THE EDGE — #{na_ev__angle_label}, hold SHIFT dragging to square the end"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Key Reminder at the End of the Status Line
        # ------------------------------------------------------------
        def na_ev__tab_hint
            return '' unless na_ev__supported?

            return '  SHIFT+click edge: push along it' unless @na_ev_lock

            na_ev__dragging? ? '  EDGE locked  SHIFT square end' : '  EDGE locked'
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
            Na__NobleDrawingTools.Na__DrawnPreview__DrawDirectionArrow(view, middle, pointing, NA_EDGE_VECTOR_COLOUR)

            return unless na_ev__dragging? && @na_point_a

            offset = na_drawn__push_offset_vector
            return unless offset && offset.length.to_f > 0.0

            na_ev__draw_line(view, @na_point_a, na_drawn__move_world_point(@na_point_a, offset), NA_EDGE_VECTOR_COLOUR, 2, '_')
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
                else ['SHIFT+click — push along this edge', "#{Na__NobleDrawingTools.Na__DrawnFormat__Mm(hover[:length]).abs} mm, #{hover[:name]}"]
                end

            Na__NobleDrawingTools.Na__DrawnPreview__DrawWorldLabel(
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
                Na__NobleDrawingTools.Na__DrawnPreview__ToDrawPoint(start),
                Na__NobleDrawingTools.Na__DrawnPreview__ToDrawPoint(finish)
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

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP PUSH PULL ALONG AN EDGE
# =============================================================================
