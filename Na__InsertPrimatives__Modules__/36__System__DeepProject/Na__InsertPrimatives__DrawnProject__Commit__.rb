# =============================================================================
# NA INSERT PRIMATIVES - DEEP PROJECT COMMIT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnProject__Commit__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnProjectCommit
# AUTHOR     : Noble Architecture
# PURPOSE    : Build a projection inside the face's own editing context
# CREATED    : 2026
#
# DESCRIPTION:
# - The preview solved every corner in world space. The commit opens the
#   face's group — the push tool's hard-won rule: an edit made from outside a
#   context leaves a stale picture — reads the face AGAIN in the space it now
#   reports, carries each corner to its world destination and brings that
#   back. No position measured before the context opened is trusted inside
#   it. Only the target and the direction cross that line, and both are
#   world, which an open context speaks.
#
# FOUR ROUTES, CHOSEN BY THE GEOMETRY:
# - FOLLOW     SHIFT+ALT. Every corner slides along its own edge to the
#              target. Nothing new is made.
# - STRETCH    Every face round this one already contains the travel (a wall
#              top rising up its own walls). The corners slide along those
#              faces and nothing new is made: no interim push, no seam, no
#              extra edge.
# - PUSH       Anything else. pushpull extrudes the face part of the way and
#              every corner of the pushed face is then placed exactly on the
#              target. Each new wall is the sweep of one edge along one
#              direction, so it stays flat whatever the target's tilt.
# - LOOP CUT   QUADS on and the target inside the material, exactly as the
#              push tool reads that gesture: nothing moves, and a ring is
#              drawn round the solid where the target crosses it.
# With QUADS on and the face going out, the start loop is put back as edges
# afterwards, as every quad push does.
#
# CUT AND EXTEND (5.2.2) — a target that crosses the face — goes by FOLLOW or
# STRETCH, where the faces round it lengthen on one side and shorten on the
# other. pushpull goes one way only, so without such faces it is refused (the
# preview says so first) rather than folding new walls back through the face.
#
# THE PUSH ROUTE PUTS THE START LINE BACK BEFORE IT PLACES ANYTHING:
# - pushpull welds a new wall into any old one it is coplanar with and
#   deletes the line between them. Placing the corners afterwards along a
#   slant would then drag that whole merged face out of its plane. So the
#   start loop is re-drawn first (the quad ring machinery, unchanged), the
#   corners are placed with the new walls standing apart from the old ones,
#   and only then are the seams that came out coplanar after all cleared
#   again — unless QUADS asked to keep them.
#
# CHECKED, NOT HOPED:
# - Every refusal the preview can see is made before anything is touched.
# - Every corner is measured where it actually landed. One that missed by a
#   tenth of a millimetre rolls the whole operation back rather than leave a
#   near miss in the model.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Focus__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Pick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Context__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'
require_relative '../30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__QuadRing__'
require_relative '../30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__Follow__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnLargeSelection__'
require_relative 'Na__InsertPrimatives__DrawnProject__Geometry__'

module Na__InsertPrimatives

    module DrawnProjectCommit

        # -----------------------------------------------------------------------------
        # REGION | The Placement
        # -----------------------------------------------------------------------------

        # FUNCTION | Place the Projection the Preview Is Showing
        # ------------------------------------------------------------
        def na_pj__commit(view)
            sources   = @na_pj_directed || []
            solutions = @na_pj_solutions || []
            target    = @na_pj_target

            problem = na_pj__refusal
            if problem
                UI.beep
                na_revise__notice("Not placed — #{problem}")
                return false
            end

            return false unless na_pj__batch_confirmed?

            model    = Sketchup.active_model
            settings = na_pj__settings
            plans    = sources.each_with_index.map { |source, index| na_pj__plan(source, solutions[index]) }
            snaps    = sources.map { |source| na_pj__snapshot(source[:target], model) }
            ghost    = na_pj__build_ghost(sources, target, settings)

            @na_pj_last_error = nil
            @na_pj_stats      = []

            placed =
                if sources.length == 1
                    na_pj__execute_single(model, sources.first, plans.first, settings)
                else
                    na_pj__execute_batch(model, sources, plans, settings)
                end

            unless placed
                UI.beep
                na_revise__notice("Projection failed: #{@na_pj_last_error}")
                na_pj__report_failure(sources, target, settings)
                na_revise__forget
                return false
            end

            # Armed while every number this projection was made from is still
            # in scope, and read back by the retype, the repeat and the ghost.
            na_pj__capture(sources, snaps, target, settings, ghost, model)
            Na__InsertPrimatives.Na__Project__RememberLast(target)
            na_pj__log(sources, solutions, target, settings)
            na_pj__warn_quads(settings)

            na_pj__forget_objects                                             # <-- The model changed; no scan is trusted past this
            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Crosses Into the Open Context: the Target and the Direction
        # ------------------------------------------------------------
        # Both world, both untouched by entering a group. Every position is
        # read again on the other side.
        # ------------------------------------------------------------
        def na_pj__plan(source, solution)
            {
                :mode   => source[:mode],
                :motion => source[:uniform] ? source[:motions][0][0] : nil,
                :normal => source[:normal],
                :plane  => solution[:plane],
                :height => solution[:plane] ? nil : solution[:heights][0][0],
                :way    => solution[:way]
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the Face's Own Space BEFORE Anything Moves It
        # The retype finds the face again by this interior point after its
        # undo, exactly as the push tool's does.
        # ------------------------------------------------------------
        def na_pj__snapshot(target, model)
            face   = target[:face]
            parent = face.parent

            {
                :entities  => parent.respond_to?(:entities) ? parent.entities : model.active_entities,
                :interior  => Na__InsertPrimatives.Na__SlopePush__InteriorPoint(face),
                :normal    => face.normal,
                :user_path => (model.respond_to?(:active_path) ? model.active_path : nil)
            }
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Backstop Before a Large Preselection Is Changed
        # Never during a retype's rebuild: that batch was placed once already.
        # ------------------------------------------------------------
        def na_pj__batch_confirmed?
            count = (@na_pj_sources || []).length
            return true if count <= NA_LARGE_SELECTION_FACES || na_revise__replaying?
            return true if Na__InsertPrimatives.Na__LargeSelection__Confirmed?(:faces, count)

            Na__InsertPrimatives.Na__LargeSelection__Ask(:faces, count, na_drawn__tool_title, 'projected', 'Project') == :yes
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Operations and Editing Contexts
        # -----------------------------------------------------------------------------

        # FUNCTION | One Face, Inside Its Own Editing Context
        # ------------------------------------------------------------
        # Enter, start, build, commit, restore — in that order, because
        # active_path= refuses to run inside an open transaction. When a context
        # was entered the operation is started transparent both ways, so
        # enter-build-restore undoes as ONE Ctrl+Z; never otherwise, or it
        # would merge into whatever the user did last. See the push commit for
        # the history of both rules.
        # ------------------------------------------------------------
        def na_pj__execute_single(model, source, plan, settings)
            target    = source[:target]
            instances = Na__InsertPrimatives.Na__DeepPick__Instances(target[:path])
            wanted    = instances.empty? ? nil : instances
            selected  = Na__InsertPrimatives.Na__DeepPick__FocusSnapshot(model)
            entered   = false
            previous  = nil

            if model.respond_to?(:active_path=)
                begin
                    previous = model.active_path
                    unless Na__InsertPrimatives.Na__DeepPick__SameContext?(previous, wanted)
                        model.active_path = wanted
                        entered = true
                    end
                rescue StandardError => error
                    entered = false
                    Na__InsertPrimatives.Na__Debug__Puts "NA PROJECT: could not open #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)} (#{error.message}) — editing from outside"
                end
            end

            name = na_pj__operation_name(plan, settings, 1)
            if entered
                model.start_operation(name, true, true, true)
            else
                model.start_operation(name, true)
            end

            placed = false
            begin
                @na_pj_stats = [na_pj__project_face(model, source, plan, settings, entered)]
                Na__InsertPrimatives.Na__DeepPick__InvalidateDefinitions(target[:path]) unless entered
                model.commit_operation
                placed = true
            rescue StandardError => error
                model.abort_operation
                @na_pj_last_error = error.message
            end

            if entered
                na_pj__restore_context(model, previous)

                # Opening the group cleared the selection, and the selection is
                # what tells the picker which group to favour.
                Na__InsertPrimatives.Na__DeepPick__FocusRestore(model, selected)
            end

            placed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Several Preselected Faces, One Operation
        # ------------------------------------------------------------
        # A selection can only hold what is in the open context, so nothing is
        # entered and every face reports world already. Each face is read
        # fresh as its turn comes: a neighbour moved by the one before it is
        # carried from where it now stands. One refusal anywhere undoes the lot.
        # ------------------------------------------------------------
        def na_pj__execute_batch(model, sources, plans, settings)
            unless sources.all? { |source| Na__InsertPrimatives.Na__DeepPick__InOpenContext?(source[:target][:face]) }
                @na_pj_last_error = 'the editing context changed — reselect the faces'
                return false
            end

            model.start_operation(na_pj__operation_name(plans.first, settings, sources.length), true)

            begin
                @na_pj_stats = sources.each_with_index.map do |source, index|
                    raise 'a projection removed another selected face — nothing was placed' unless source[:target][:face].valid?

                    na_pj__project_face(model, source, plans[index], settings, false)
                end

                model.commit_operation
                true
            rescue StandardError => error
                model.abort_operation
                @na_pj_last_error = error.message
                false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put the User Back in the Context They Were In
        # Falls back to the model root rather than ever leaving them stranded
        # inside the group this tool opened.
        # ------------------------------------------------------------
        def na_pj__restore_context(model, previous)
            model.active_path = previous
        rescue StandardError
            begin
                model.active_path = nil
            rescue StandardError
                nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Undo Menu Calls It
        # ------------------------------------------------------------
        def na_pj__operation_name(plan, settings, count)
            detail =
                if    count > 1                                   then 'Selected Faces'
                elsif plan[:mode] == :follow                      then 'Follow'
                elsif settings[:quads] && plan[:way] == :in       then 'Loop Cut'
                elsif plan[:way] == :mixed                        then 'Cut and Extend'
                elsif settings[:quads]                            then 'Quads'
                else  nil
                end

            detail ? "Deep Project (#{detail})" : 'Deep Project'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | One Face
        # -----------------------------------------------------------------------------

        # FUNCTION | Carry One Face to Its Target, Inside the Open Operation
        # ------------------------------------------------------------
        # THE SPACE THE FACE REPORTS, BY THE COORDINATE RULE:
        # - Entered, or already standing in the open context: global. Every
        #   read and every move is world, and the transform is the identity.
        # - Not entered (active_path= refused): the definition's own space, and
        #   the pick's transformation carries it to world and back.
        # Positions are converted at the edges of this function and nowhere
        # else; directions travel as two points, never as bare vectors.
        # ------------------------------------------------------------
        def na_pj__project_face(model, source, plan, settings, entered)
            target = source[:target]
            face   = target[:face]
            raise 'that face is no longer available' unless face && face.valid?

            xform  = entered ? Geom::Transformation.new : (target[:transformation] || Geom::Transformation.new)
            parent = face.parent
            quads  = settings[:quads] ? true : false

            job = {
                :model        => model,
                :entities     => parent.respond_to?(:entities) ? parent.entities : model.active_entities,
                :face         => face,
                :xform        => xform,
                :inverse      => xform.inverse,
                :plan         => plan,
                :quads        => quads,
                :entered      => entered,
                :normal_scale => (target[:normal_scale] || 1.0).to_f,
                :loops        => Na__InsertPrimatives.Na__PushPull__CaptureLoops(face)      # <-- Where it started, cloned, before anything moves
            }

            cut = quads && plan[:way] == :in

            if plan[:mode] == :follow
                na_pj__route_follow(job, cut)
            elsif cut
                na_pj__route_cut(job)
            elsif na_pj__can_stretch?(job)
                na_pj__route_stretch(job)
            elsif plan[:way] == :mixed
                # pushpull goes one way only, and a cut and extend goes both:
                # without faces round it to slide along, the walls would fold
                # through the face. The preview refuses this first; this is
                # the backstop.
                raise NA_PROJECT_MIXED_REFUSAL
            else
                na_pj__route_push(job)
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Routes
        # -----------------------------------------------------------------------------

        # FUNCTION | FOLLOW — Every Corner Along Its Own Edge to the Target
        # ------------------------------------------------------------
        # The rails are read here, inside the operation, in the space the face
        # reports now; each is carried to world as two points, solved, and
        # brought back. A corner may not run past the far end of the edge it
        # follows.
        # ------------------------------------------------------------
        def na_pj__route_follow(job, cut)
            face  = job[:face]
            found = Na__InsertPrimatives.Na__FollowPush__Rails(face)
            raise "follow: #{found[:reason]}" unless found[:ok]

            normal   = job[:plan][:normal]
            landed   = {}
            vertices = []
            vectors  = []

            found[:rails].each do |rail|
                start  = rail[:point].transform(job[:xform])
                ahead  = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(rail[:point], rail[:dir], 1.0).transform(job[:xform])
                motion = Na__InsertPrimatives.Na__Project__Motion(ahead - start, normal, 0.0)
                raise 'follow: an edge this face would follow runs along it' unless motion

                height = na_pj__height(job[:plan], start, motion)
                dest   = Na__InsertPrimatives.Na__Project__Lift(start, motion, height).transform(job[:inverse])
                vector = dest - rail[:point]

                if height < 0.0 && vector.length.to_f > rail[:inward].to_f + NA_PROJECT_TOL
                    raise 'follow: the target lies past the end of an edge it follows'
                end

                landed[rail[:vertex].entityID] = dest
                vertices << rail[:vertex]
                vectors  << vector
            end

            if cut
                rings = face.loops.map { |loop| loop.vertices.map { |vertex| landed[vertex.entityID] } }
                raise 'follow: a corner of the ring could not be placed' if rings.flatten.any?(&:nil?)

                return { :route => :follow_cut, :quad => na_pj__stitch(job, rings) }
            end

            na_pj__move_vertices(job, vertices, vectors)
            { :route => :follow, :quad => (job[:quads] ? na_pj__stitch(job, job[:loops]) : nil) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | LOOP CUT — A Ring Where the Target Crosses the Solid
        # The ring lands in the faces round this one only where they are the
        # sweep of it along the travel; where they are not, the ring bounds
        # nothing and the quad machinery sweeps it straight back off.
        # ------------------------------------------------------------
        def na_pj__route_cut(job)
            rings = job[:loops].map do |points|
                points.map { |point| na_pj__destination_reported(job, point) }
            end

            { :route => :cut, :quad => na_pj__stitch(job, rings) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | STRETCH — Slide the Corners Along Faces That Already Hold the Travel
        # ------------------------------------------------------------
        def na_pj__route_stretch(job)
            vertices = job[:face].vertices
            vectors  = vertices.map { |vertex| na_pj__vertex_vector(job, vertex) }

            na_pj__move_vertices(job, vertices, vectors)
            { :route => :stretch, :quad => (job[:quads] ? na_pj__stitch(job, job[:loops]) : nil) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | PUSH — pushpull Part of the Way, Then Place Every Corner
        # ------------------------------------------------------------
        # How far the interim push goes does not matter — every corner is
        # placed afterwards, and the pushed face is found by looking rather
        # than by trusting the distance — but which way it goes does: out of
        # the solid is an extrusion, into it a cut.
        #
        # A slanted cut back into the solid is refused when a face round this
        # one runs along its normal: the push would trim that face, and the
        # slant would then have to bend it.
        # ------------------------------------------------------------
        def na_pj__route_push(job)
            face     = job[:face]
            normal   = face.normal
            interior = Na__InsertPrimatives.Na__SlopePush__InteriorPoint(face)
            raise 'the face has no inside to find it by after the push' unless interior

            lift = na_pj__mean_lift(job)
            raise 'the face would not move' if lift.abs < NA_PROJECT_TOL

            if job[:plan][:way] == :in && !na_pj__along_normal?(job[:plan]) && na_pj__merge_risk?(face)
                raise 'cutting back at a slant needs every face round it to run that way too — TAB QUADS marks the line instead'
            end

            scale    = job[:normal_scale] > 0.0 ? job[:normal_scale] : 1.0
            distance = lift / scale
            face.pushpull(distance)

            expected     = job[:entered] ? lift : distance
            moved, delta = na_pj__pushed_face(job[:entities], face, interior, normal, expected)
            raise 'the pushed face could not be found again to place its corners' unless moved

            ring = na_pj__stitch(job, job[:loops])                           # <-- The start line back, so no merged wall is bent

            vertices = moved.vertices
            vectors  = vertices.map do |vertex|
                began = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(vertex.position, normal, -delta)
                na_pj__destination_reported(job, began) - vertex.position
            end

            na_pj__move_vertices(job, vertices, vectors)

            healed = job[:quads] ? 0 : Na__InsertPrimatives.Na__SlopePush__HealSeam(moved)
            { :route => :push, :quad => (job[:quads] ? ring : nil), :healed => healed }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Where Corners Go, in the Space the Face Reports
        # -----------------------------------------------------------------------------

        # FUNCTION | A Corner's Height Along a Motion, by the Plan
        # ------------------------------------------------------------
        def na_pj__height(plan, world, motion)
            height = plan[:plane] ? Na__InsertPrimatives.Na__Project__HeightToPlane(world, motion, plan[:plane]) : plan[:height]
            raise 'a corner could not be carried to the target' if height.nil?

            height.to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | A World Point Carried to the Target
        # ------------------------------------------------------------
        def na_pj__destination(plan, world, motion = nil)
            motion ||= plan[:motion]
            raise 'there is no direction to carry the face along' unless motion

            Na__InsertPrimatives.Na__Project__Lift(world, motion, na_pj__height(plan, world, motion))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Reported Point Carried to the Target, Back in Reported Space
        # ------------------------------------------------------------
        def na_pj__destination_reported(job, point)
            na_pj__destination(job[:plan], point.transform(job[:xform])).transform(job[:inverse])
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far a Vertex Has to Move, in Reported Space
        # ------------------------------------------------------------
        def na_pj__vertex_vector(job, vertex)
            position = vertex.position
            na_pj__destination_reported(job, position) - position
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Travel as a Reported-Space Unit Direction
        # Two points, carried and subtracted: the rule every space change here
        # follows, so a translation can never leak into a direction.
        # ------------------------------------------------------------
        def na_pj__reported_direction(job)
            origin = job[:face].vertices.first.position
            ahead  = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin.transform(job[:xform]), job[:plan][:motion], 1.0)
            vector = ahead.transform(job[:inverse]) - origin

            vector.length.to_f > 0.0 ? vector.normalize : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Average Lift Off the Face's Plane, World, Signed
        # ------------------------------------------------------------
        def na_pj__mean_lift(job)
            normal = job[:plan][:normal]
            lifts  = job[:face].vertices.map do |vertex|
                world = vertex.position.transform(job[:xform])
                (na_pj__destination(job[:plan], world) - world).dot(normal).to_f
            end

            lifts.inject(0.0) { |sum, value| sum + value } / lifts.length
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Route Tests
        # -----------------------------------------------------------------------------

        # FUNCTION | Can the Corners Simply Slide to the Target?
        # ------------------------------------------------------------
        # Every face touching this one must already contain the travel (the
        # slope tool's own test), and going in, every corner must have room to
        # run back along the edge behind it. A box cannot be cut back past its
        # own far end, and that is refused outright rather than handed to
        # pushpull, which would make a worse job of it. A corner with no edge
        # running straight back at all is left to pushpull, which is what
        # native Push/Pull would have done there.
        # ------------------------------------------------------------
        def na_pj__can_stretch?(job)
            return false unless job[:plan][:motion]

            direction = na_pj__reported_direction(job)
            return false unless direction
            return false unless Na__InsertPrimatives.Na__SlopePush__CanStretch?(job[:face], direction)
            return true if job[:plan][:way] == :out

            room = na_pj__inward_room(job, direction)
            raise 'the target lies past the far end of the solid along this direction' if room == :short

            room == :ok
        end
        # ---------------------------------------------------------------

        # FUNCTION | Has Every Corner Going Back Room to Run? :ok, :short or :unknown
        # ------------------------------------------------------------
        # Only the corners going back are asked: in a cut and extend the ones
        # going out have all the room they want.
        # ------------------------------------------------------------
        def na_pj__inward_room(job, direction)
            face    = job[:face]
            short   = false
            unknown = false

            face.vertices.each do |vertex|
                world = vertex.position.transform(job[:xform])
                next unless na_pj__height(job[:plan], world, job[:plan][:motion]) < 0.0

                travel = na_pj__vertex_vector(job, vertex).length.to_f
                next if travel < NA_PROJECT_TOL

                own   = vertex.edges.select { |edge| edge.faces.include?(face) }
                reach = Na__InsertPrimatives.Na__FollowPush__InwardReach(vertex, own, direction)

                if reach <= 0.0
                    unknown = true
                elsif reach <= travel + NA_PROJECT_TOL
                    short = true
                end
            end

            return :short   if short
            return :unknown if unknown

            :ok
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Travel the Face Normal Itself?
        # m . n = 1 by construction, so a motion of unit length IS the normal.
        # ------------------------------------------------------------
        def na_pj__along_normal?(plan)
            motion = plan[:motion]
            return true unless motion

            (motion.length.to_f - 1.0).abs < 1.0e-6
        end
        # ---------------------------------------------------------------

        # FUNCTION | Would a Push Weld a New Wall Into a Face Round This One?
        # A neighbour that runs along the normal is coplanar with the wall the
        # push makes on that edge.
        # ------------------------------------------------------------
        def na_pj__merge_risk?(face)
            normal = face.normal

            face.edges.any? do |edge|
                edge.faces.any? do |other|
                    other != face && other.normal.dot(normal).abs <= NA_SLOPE_PUSH_IN_PLANE
                end
            end
        rescue StandardError
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Moving and Stitching
        # -----------------------------------------------------------------------------

        # FUNCTION | Move Vertices by Their Own Vectors, Then Prove Where They Landed
        # ------------------------------------------------------------
        # One transform_by_vectors for the lot, so every face round them goes
        # from one flat shape to the next in a single step, never through a
        # bent one. A corner already on the target is left out of the move but
        # still measured.
        # ------------------------------------------------------------
        def na_pj__move_vertices(job, vertices, vectors)
            wanted = vertices.each_with_index.map do |vertex, index|
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(vertex.position, vectors[index], 1.0)
            end

            moving = []
            pushes = []

            vertices.each_with_index do |vertex, index|
                next if vectors[index].length.to_f < NA_PROJECT_TOL * 0.25

                moving << vertex
                pushes << vectors[index]
            end
            return 0 if moving.empty?

            job[:entities].transform_by_vectors(moving, pushes)

            vertices.each_with_index do |vertex, index|
                raise 'a corner merged into another as it moved — nothing was changed' unless vertex.valid?
                next if vertex.position.distance(wanted[index]).to_f < NA_PROJECT_TOL

                raise 'a corner did not land on the target — nothing was changed'
            end

            moving.length
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw Rings of Reported Points Into the Faces Round Them
        # The push tool's quad ring, unchanged: it checks where the ring
        # landed, removes any fill face a closed ring makes, and sweeps off
        # every edge that ended up bounding nothing.
        # ------------------------------------------------------------
        def na_pj__stitch(job, rings)
            rings = (rings || []).reject { |points| points.nil? || points.length < 3 }
            return nil if rings.empty?

            build = Na__InsertPrimatives.Na__DeepPick__AddTransform(job[:model], job[:entities], rings.first.first)
            Na__InsertPrimatives.Na__PushPull__StitchQuadRing(job[:entities], rings, build)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Face Did pushpull Leave at the Far End?
        # ------------------------------------------------------------
        # Found by looking, as the slope push finds it: the face whose plane
        # stands off the original on the pushed side and holds the interior
        # point carried square across to it. Of several, the one nearest the
        # distance expected.
        # ------------------------------------------------------------
        def na_pj__pushed_face(entities, face, interior, normal, expected)
            best = nil

            ([face] + entities.grep(Sketchup::Face)).each do |candidate|
                next unless candidate.valid?
                next unless candidate.normal.samedirection?(normal)

                delta = (candidate.vertices.first.position - interior).dot(normal).to_f
                next unless delta * expected > 0.0 && delta.abs > NA_PROJECT_TOL

                probe = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(interior, normal, delta)
                next unless candidate.classify_point(probe) == Sketchup::Face::PointInside

                gap  = (delta - expected).abs
                best = [candidate, delta, gap] if best.nil? || gap < best[2]
            end

            best ? [best[0], best[1]] : [nil, nil]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Reports
        # -----------------------------------------------------------------------------

        # FUNCTION | Say So When QUADS Built Nothing
        # A quad line that does not appear is exactly as broken as one in the
        # wrong place, and a loop cut that kept nothing did nothing at all.
        # ------------------------------------------------------------
        def na_pj__warn_quads(settings)
            return false unless settings[:quads]

            empty = (@na_pj_stats || []).any? do |stats|
                quad = stats && stats[:quad]
                quad.nil? || quad[:kept].to_i.zero?
            end
            return false unless empty

            cut = (@na_pj_stats || []).any? { |stats| stats && [:cut, :follow_cut].include?(stats[:route]) }
            UI.beep
            na_revise__notice(
                cut ? 'No loop cut — the faces round this one do not run along the travel' :
                      'Placed, but the quad line built nothing — see the console'
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Projection
        # ------------------------------------------------------------
        def na_pj__log(sources, solutions, target, settings)
            first = sources.first

            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts(na_revise__replaying? ? 'DEEP PROJECT ADJUSTED (retyped offset)' : 'DEEP PROJECT APPLIED')
            Na__InsertPrimatives.Na__Debug__Puts "Faces    : #{sources.length} — first in #{Na__InsertPrimatives.Na__DeepPick__PathLabel(first[:target])}"
            Na__InsertPrimatives.Na__Debug__Puts "Target   : #{target[:kind].to_s.upcase} — #{target[:name]}"
            Na__InsertPrimatives.Na__Debug__Puts "Direction: #{first[:words]}"
            Na__InsertPrimatives.Na__Debug__Puts "Travel   : #{Na__InsertPrimatives.Na__Project__TravelText(solutions.map { |solution| solution[:travels] })} mm"
            Na__InsertPrimatives.Na__Debug__Puts "Offset   : #{na_pj__offset_words(settings[:offset])}"
            Na__InsertPrimatives.Na__Debug__Puts "Routes   : #{(@na_pj_stats || []).map { |stats| stats ? stats[:route] : '?' }.join(', ')}"
            Na__InsertPrimatives.Na__Debug__Puts "Quads    : #{settings[:quads] ? 'ON' : 'off'}"
            Na__InsertPrimatives.Na__Debug__Puts "Instances affected: #{first[:target][:shared_count]}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA PROJECT: placed, and the report itself failed (#{error.message})"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say Out Loud Why a Projection Was Refused
        # ------------------------------------------------------------
        def na_pj__report_failure(sources, target, settings)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts 'DEEP PROJECT REFUSED'
            Na__InsertPrimatives.Na__Debug__Puts "Reason   : #{@na_pj_last_error}"
            Na__InsertPrimatives.Na__Debug__Puts "Faces    : #{sources.length}"
            Na__InsertPrimatives.Na__Debug__Puts "Target   : #{target ? "#{target[:kind].to_s.upcase} — #{target[:name]}" : 'none'}"
            Na__InsertPrimatives.Na__Debug__Puts "Direction: #{sources.first ? sources.first[:words] : 'n/a'}"
            Na__InsertPrimatives.Na__Debug__Puts "Offset   : #{na_pj__offset_words(settings[:offset])}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA PROJECT: refused, and the report itself failed (#{error.message})"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnProjectCommit module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PROJECT COMMIT
# =============================================================================
