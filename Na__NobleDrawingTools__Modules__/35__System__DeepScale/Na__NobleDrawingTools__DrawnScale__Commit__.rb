# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP SCALE COMMIT
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnScale__Commit__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Put a scale or a stretch into the model as one undo step
# CREATED    : 2026
#
# DESCRIPTION:
# - Two ways in, chosen by the field:
#   SCALE    no axis stretches, so the object's own transformation is
#            changed and nothing inside it is touched — what SketchUp's Scale
#            tool does, and why a scaled copy of a component stays a copy.
#   STRETCH  an axis has planes, so the geometry itself moves: every vertex
#            goes where the field sends it, a nested group with no plane
#            through it is carried whole, and one with a plane through it is
#            opened and stretched the same way, all the way down.
# - Loose geometry has no transformation or definition of its own, so its
#   points move either way, where they lie (5.2.9, 5.2.22).
# - A SELECTION of several objects (5.2.41) is boxed as one, in the axes of the
#   open context. A scale changes each object's transformation, as SketchUp's
#   own Scale does. A stretch carries whole every object no plane runs through
#   and opens every object a plane does run through, stretching it from inside
#   its own context by the same walk as a single object, so two walls selected
#   together stretch as one wall would. Until 5.2.41 those were carried whole,
#   which moved them apart while the preview showed them stretching.
#
# ONE OBJECT CHANGES, NOT EVERY COPY:
# - A stretch edits a definition, and a definition can be shared. Scaling one
#   window must not resize every window of its type, so a shared object is
#   made unique first, and so is any shared part inside it that a plane runs
#   through. Its stretch planes are copied across, so the unique copy still
#   knows where it stretches. Parts carried whole stay shared.
#
# COPIES THAT STRETCH ALIKE STAY ONE COMPONENT (5.2.43):
# - Until 5.2.43 every shared part a plane ran through was made unique on its
#   own: thirty balusters stretched taller came out as thirty definitions,
#   each opened and stretched in turn. Now the stretch is planned before
#   anything moves (04__GeometryHelpers/..DrawnDeepUnique__.rb). Every object
#   and part the walk would open is a node, signed with where the field sends
#   every point of it, read in its own axes. Copies with one signature stay
#   (or become) one definition and only one of them is opened and stretched;
#   the rest follow as copies do. A definition all of whose copies in the
#   whole model are in the stretch, alike, is stretched as it is; otherwise
#   the copies in the stretch are moved onto a definition of their own
#   (make_unique, then definition=), planes copied across, and the copies
#   elsewhere keep the old one.
# - A part reached by double-clicking down is planned with the containers
#   above it: a shared container is made unique too, so a baluster stretched
#   inside one of two copies of a balustrade changes that balustrade only.
#   Its copy then stands in the new container, and the tool is handed its
#   new path (:live_path).
# - The split happens where make_unique belongs: each copy closed, in the
#   open context of its container, just before that container's own edit.
#
# EVERY DEFINITION IS EDITED FROM INSIDE ITS OWN CONTEXT (5.2.6):
# - Geometry edited from outside its editing context lands in the model but
#   SketchUp never rebuilds that instance's display (the 0.4.19 lesson, and
#   the rule in the DeepPick hub). Until 5.2.6 the object was opened but the
#   parts a plane runs through were still edited from outside, from the
#   object's context. Now the stretch walks down one context at a time: the
#   object, then each part a plane runs through, then the parts inside
#   those. In each, everything reports GLOBAL coordinates (the 5.1.2 rule),
#   so a point goes to the object's axes through frame[:inverse], through
#   the field, and back through frame[:world]. No edit_transform in the
#   maths, and nothing ever edited from outside.
# - A part with no plane through it is carried whole from its parent's
#   context, where its transformation reads as world. A shared part a plane
#   runs through is made unique there, closed, before its own turn.
#
# ONE UNDO STEP:
# - Entering a context is an undo step of its own. Every edit in the walk
#   starts transparent (it joins the step before it) and next_transparent
#   (it pulls in the next entry: the next context, or the final restore of
#   the user's own context). The object always sits below the user's context,
#   so that restore always comes, and no next_transparent is ever left
#   waiting for the user's next action. A make_unique of the object itself
#   has to happen before its context opens, so it runs first, in the user's
#   context, with next_transparent set.
#
# WELDED CURVES (5.2.18):
# - SketchUp re-fits a welded curve (arc, circle, welded run) round any of
#   its vertices that is moved on its own, so a stretch warped them. Every
#   curve with a vertex in the stretch is exploded just before the move and
#   welded back after it (04__GeometryHelpers/..CurveUnweld__.rb). Loose
#   geometry scaled unevenly gets the same; a uniform scale leaves arcs as
#   arcs and is not touched. A plain scale changes only the instance.
#
# NEVER CLOSED ALL THE WAY:
# - Na__ScaleCommit__CheckRoom measures the real geometry before anything is
#   touched and refuses a shrink that would bring details either side of a
#   plane within NA_SCALE_MIN_GAP of each other. The tool's drag limit reads
#   the same rule from its ghost; this is the last word, for an object too
#   big for the ghost to have seen every point of.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__CurveUnweld__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepUnique__'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Commit Constants
    # -----------------------------------------------------------------------------

    NA_SCALE_OP_SCALE   = 'Deep Scale'.freeze
    NA_SCALE_OP_STRETCH = 'Deep Scale (Stretch)'.freeze
    NA_SCALE_OP_PLANE   = 'Stretch Plane'.freeze
    NA_SCALE_OP_REMOVE  = 'Remove Stretch Plane'.freeze
    NA_SCALE_OP_CLEAR   = 'Clear Stretch Planes'.freeze
    NA_SCALE_MOVE_TOL   = 1e-7                                                # <-- Inches; a vertex moved less than this is left alone
    NA_SCALE_MAX_DEPTH  = 16

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Commit a Field to the Model
    # ------------------------------------------------------------
    # planes_after is the plane set the stretch leaves behind (see
    # Na__ScaleField__PlanesAfter), ignored by a plain scale.
    #
    # Returns { :success, :error, :mode, :unique, :rigid, :opened, :moved }.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Run(model, frame, field, planes_after = nil)
        return { :success => false, :error => 'nothing to change' } if Na__NobleDrawingTools.Na__ScaleField__Identity?(field)
        return { :success => false, :error => 'the sizes worked out to nonsense — nothing was changed' } unless Na__NobleDrawingTools.Na__ScaleField__Finite?(field)

        if frame[:loose]
            return Na__NobleDrawingTools.Na__ScaleCommit__StretchLoose(model, frame, field) if field[:stretch]
            return Na__NobleDrawingTools.Na__ScaleCommit__ScaleLoose(model, frame, field)
        end

        if field[:stretch]
            Na__NobleDrawingTools.Na__ScaleCommit__Stretch(model, frame, field, planes_after)
        else
            Na__NobleDrawingTools.Na__ScaleCommit__Scale(model, frame, field)
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Plain Scale — the Object's Own Transformation
    # -----------------------------------------------------------------------------

    # FUNCTION | Scale the Instance, Leaving Its Definition Alone
    # ------------------------------------------------------------
    # The field over the whole box is one local transformation A. In world
    # that is world * A * world⁻¹, applied with transform! from the context
    # the object lives in — where its transformation reads as world, whether
    # that is the user's own context or one opened to reach a nested target.
    # If the open fails the instance reports local to its parent, so the
    # change is taken into the parent's space instead.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Scale(model, frame, field)
        instance    = frame[:instance]
        parent_path = Na__NobleDrawingTools.Na__DeepPick__Instances(frame[:path])[0...-1]
        local       = Na__NobleDrawingTools.Na__ScaleField__Affine(field, frame[:min])
        world_delta = frame[:world] * local * frame[:inverse]
        parent      = parent_path.empty? ? nil : Na__NobleDrawingTools.Na__ScaleFrame__WorldTransform(parent_path)

        result = Na__NobleDrawingTools.Na__DeepPick__ExecuteInContext(model, parent_path, NA_SCALE_OP_SCALE) do |_entered|
            wanted   = parent_path.empty? ? nil : parent_path
            in_world = Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, wanted) || parent.nil?
            delta    = in_world ? world_delta : (parent.inverse * world_delta * parent)

            instance.transform!(delta)
        end

        result.merge(:mode => :scale, :unique => 0, :rigid => 0, :opened => 0, :moved => 0)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Scale Loose Geometry Where It Lies, in the Open Context
    # ------------------------------------------------------------
    # Loose geometry has no transformation of its own to change, so its
    # points move: one transform_entities with the field over the box as a
    # world transformation, world * A * world⁻¹. The entities sit in the open
    # context, which takes world (the coordinate rule; documented for
    # transform_entities), so nothing is converted. Groups in the selection
    # take the same transformation whole, as with SketchUp's own Scale.
    # Refused if the user has since moved to another context: the entities
    # are no longer in the one that is open.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__ScaleLoose(model, frame, field)
        result = { :success => false, :error => nil, :mode => :scale, :unique => 0, :rigid => 0, :opened => 0, :moved => 0 }

        unless Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, frame[:context])
            return result.merge(:error => 'the open group changed since the geometry was taken — select it again')
        end

        list = frame[:entities].select(&:valid?)
        return result.merge(:error => 'the geometry is no longer there') if list.empty?

        delta = frame[:world] * Na__NobleDrawingTools.Na__ScaleField__Affine(field, frame[:min]) * frame[:inverse]
        model.start_operation(NA_SCALE_OP_SCALE, true)

        begin
            # A uniform scale keeps every arc an arc; anything else cannot, and
            # SketchUp re-fits a welded curve it cannot keep (WELDED CURVES).
            chains = []
            unless Na__NobleDrawingTools.Na__ScaleCommit__Uniform?(delta)
                loose_vertices = list.flat_map { |entity| entity.respond_to?(:vertices) ? entity.vertices : [] }
                chains         = Na__NobleDrawingTools.Na__CurveUnweld__Explode(loose_vertices)
            end

            model.active_entities.transform_entities(delta, list)
            Na__NobleDrawingTools.Na__CurveUnweld__Reweld(model.active_entities, chains)
            model.commit_operation
            result.merge(:success => true, :moved => list.length)
        rescue StandardError => error
            model.abort_operation
            result.merge(:error => error.message)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does a Transformation Scale Every Direction Alike?
    # ------------------------------------------------------------
    # Its three axis columns the same length and square to each other: a
    # rotation, a move and one scale factor, under which an arc stays an arc.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Uniform?(transformation)
        m    = transformation.to_a
        axes = [[m[0], m[1], m[2]], [m[4], m[5], m[6]], [m[8], m[9], m[10]]]
        size = axes.map { |a| Math.sqrt((a[0] * a[0]) + (a[1] * a[1]) + (a[2] * a[2])) }
        return false if size.min <= 0.0

        dot  = lambda { |a, b| ((a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])) / (Math.sqrt((a[0] * a[0]) + (a[1] * a[1]) + (a[2] * a[2])) * Math.sqrt((b[0] * b[0]) + (b[1] * b[1]) + (b[2] * b[2]))) }
        same = (size.max - size.min) <= (1e-6 * size.max)
        same && dot.call(axes[0], axes[1]).abs < 1e-6 && dot.call(axes[1], axes[2]).abs < 1e-6 && dot.call(axes[0], axes[2]).abs < 1e-6
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Stretch — the Geometry Itself
    # -----------------------------------------------------------------------------

    # FUNCTION | Stretch the Object at Its Planes
    # ------------------------------------------------------------
    # The walk in the header: the object's context first, then every part a
    # plane runs through, one context at a time, outermost first. Each edit
    # hands back the parts below it that need their own turn.
    #
    # Planned first (5.2.43): the object, the containers above it below the
    # user's context, and every part the walk will open are nodes, so each
    # shared definition is decided once against the whole model. The copy
    # standing in the user's context is settled there; everything else in
    # the context of its container, on the way down.
    #
    # A context that will not open stops the walk there, and the user's own
    # context is put back either way. Nothing is ever edited from outside.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Stretch(model, frame, field, planes_after)
        path   = Na__NobleDrawingTools.Na__DeepPick__Instances(frame[:path])
        tally  = { :unique => 0, :rigid => 0, :opened => 0, :moved => 0, :base => path.length }
        failed = Na__NobleDrawingTools.Na__ScaleCommit__CheckRoom(frame, field)
        return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, failed, tally) if failed

        plan, object = Na__NobleDrawingTools.Na__ScaleCommit__PlanObject(model, frame, field, path)
        return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, plan[:refused], tally, plan) if plan[:refused]

        previous = model.active_path
        selected = Na__NobleDrawingTools.Na__DeepPick__FocusSnapshot(model)  # <-- Entering a context clears this
        pending  = false                                                    # <-- An edit committed next_transparent, its next entry still to come
        base     = Array(previous)

        if Na__NobleDrawingTools.Na__DeepUnique__NeedsSettle?(plan, plan[:roots])
            model.start_operation(NA_SCALE_OP_STRETCH, true, true, false)     # <-- next_transparent: the object's context entry joins this step

            begin
                queue = Na__NobleDrawingTools.Na__ScaleCommit__Settle(plan, plan[:roots], model.active_entities, base)
                model.commit_operation
                pending = true
            rescue StandardError => error
                model.abort_operation
                return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, "could not make #{frame[:name]} unique — #{error.message}", tally, plan)
            end
        else
            begin
                queue = Na__NobleDrawingTools.Na__ScaleCommit__Settle(plan, plan[:roots], model.active_entities, base)  # <-- Only found again: nothing changes
            rescue StandardError => error
                return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, error.message, tally, plan)
            end
        end

        failed, pending = Na__NobleDrawingTools.Na__ScaleCommit__Walk(model, frame, field, queue, tally, pending, plan) do |target, node|
            Na__NobleDrawingTools.Na__ScalePlanes__Write(target.last.definition, planes_after) if planes_after && node.equal?(object)
        end

        restored = Na__NobleDrawingTools.Na__ScaleCommit__Restore(model, previous)
        Na__NobleDrawingTools.Na__ScaleCommit__ClosePending(model) if pending && !restored
        Na__NobleDrawingTools.Na__DeepPick__FocusRestore(model, selected)

        result = Na__NobleDrawingTools.Na__ScaleCommit__Result(failed.nil?, failed, tally, plan)
        live   = object[:live]
        result[:live_path] = base + Na__NobleDrawingTools.Na__DeepUnique__LivePath(object) if live && live.valid? && !live.equal?(frame[:instance])
        result
    end
    # ---------------------------------------------------------------

    # FUNCTION | Stretch a Queue of Contexts, Each From Inside; Returns [failed, pending]
    # ------------------------------------------------------------
    # The walk in the header, shared by a single object and a selection
    # (5.2.41). The queue holds [path, node] pairs from the plan (5.2.43).
    # Each target is opened, stretched by StretchContext, and the parts it
    # hands back join the queue. A container above a picked part (:via) is
    # opened only when something in it has to be settled; otherwise what is
    # below it is found where it stands. pending comes in as the caller left
    # it (a settle committed next_transparent) and goes back out true while
    # an edit's next entry is still to come. The block, when given, runs
    # inside each target's operation: the object's own planes are written
    # there. A context that will not open stops the walk; the caller restores
    # the user's context either way.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Walk(model, frame, field, queue, tally, pending, plan)
        failed = nil

        until queue.empty?
            target, node = queue.shift
            via          = node[:payload][:role] == :via

            if via && !Na__NobleDrawingTools.Na__DeepUnique__NeedsSettle?(plan, node[:children])
                begin
                    queue.unshift(*Na__NobleDrawingTools.Na__ScaleCommit__Settle(plan, node[:children], node[:live].definition.entities, target))
                rescue StandardError => error
                    failed = error.message
                    break
                end

                next
            end

            unless Na__NobleDrawingTools.Na__ScaleCommit__Enter(model, target)
                failed = "#{Na__NobleDrawingTools.Na__DeepPick__InstanceName(target.last)} would not open for editing — the stretch stopped there; Ctrl+Z takes back what was done"
                break
            end

            pending = false
            model.start_operation(NA_SCALE_OP_STRETCH, true, true, true)      # <-- Joins the entry just made, pulls in the next

            begin
                if via
                    queue.concat(Na__NobleDrawingTools.Na__ScaleCommit__Settle(plan, node[:children], model.active_entities, target))
                else
                    queue.concat(Na__NobleDrawingTools.Na__ScaleCommit__StretchContext(model, frame, field, target, tally, plan, node))
                    yield(target, node) if block_given?
                end
            rescue StandardError => error
                failed = "#{error.message} — the stretch stopped there; Ctrl+Z takes back what was done"
            end

            model.commit_operation                                            # <-- Never abort a transparent operation (ruby.sketchup.com): it aborts the one it joined
            pending = true
            break if failed
        end

        [failed, pending]
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Stretch's Answer in the Shape the Tool Reads
    # ------------------------------------------------------------
    # :unique counts the definitions made; :copies the copies that were
    # stretched through another copy's one edit; :shared says so in words.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Result(success, error, tally, plan = nil)
        {
            :success => success,
            :error   => error,
            :mode    => :stretch,
            :unique  => plan ? plan[:made] : tally[:unique],
            :rigid   => tally[:rigid],
            :opened  => tally[:opened],
            :moved   => tally[:moved],
            :copies  => plan ? plan[:riders].values.sum : 0,
            :shared  => plan ? Na__NobleDrawingTools.Na__DeepUnique__Report(plan) : ''
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open One Context; True Only Once It Really Is the Open One
    # ------------------------------------------------------------
    # active_path= refuses to run inside an open operation, so this is only
    # ever called between them.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Enter(model, target)
        return true if Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, target)

        model.active_path = target
        Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, target)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put the User Back Where They Were; True If the Context Changed
    # Falls back to the root rather than ever leaving them inside a part the
    # stretch opened.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Restore(model, previous)
        return false if Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, previous)

        begin
            model.active_path = previous
        rescue StandardError
            begin
                model.active_path = nil
            rescue StandardError
                nil
            end
        end

        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Take Up a next_transparent Nothing Followed
    # Only when the object itself would not open after being made unique: an
    # empty edit joins the make_unique step, so the user's next action does
    # not silently become part of it.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__ClosePending(model)
        model.start_operation(NA_SCALE_OP_STRETCH, true, false, true)
        model.commit_operation
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Stretch the Open Context's Own Geometry; Return the Parts Next in Line
    # ------------------------------------------------------------
    # Called with target open, so everything in it reports global — the
    # vertices, and the transformations of the closed parts directly inside
    # it. frame[:inverse] takes a global point into the object's own axes,
    # where the field is defined, and frame[:world] brings the answer back.
    # Asserted, not assumed: a wrong context would move every point by the
    # difference between two spaces.
    #
    # Which parts a plane runs through was settled on paper (5.2.43): they
    # are node's children in the plan, the same test (RigidOver? and the
    # depth guard) worked out from the same transformations. Each is found
    # again here, settled onto its final definition while still closed, and
    # one copy of each final definition is handed back for its turn; the
    # copies riding on it are neither opened nor carried. Every other part
    # is carried whole. Returns [path, node] pairs.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__StretchContext(model, frame, field, target, tally, plan, node)
        unless Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, target)
            raise ArgumentError, "#{Na__NobleDrawingTools.Na__DeepPick__InstanceName(target.last)} is not the open context"
        end

        world    = frame[:world]
        inverse  = frame[:inverse]
        entities = model.active_entities
        vertices = {}
        parts    = []

        entities.each do |entity|
            if entity.is_a?(Sketchup::Edge)
                entity.vertices.each { |vertex| vertices[vertex.entityID] ||= vertex }
            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                parts << entity
            end
        end

        tally[:moved] += Na__NobleDrawingTools.Na__ScaleCommit__MoveVertices(entities, vertices, frame, field)

        if target.length > tally[:base]
            Na__NobleDrawingTools.Na__ScaleCommit__CarryPartPlanes(target.last, inverse * model.edit_transform, field)
            tally[:opened] += 1
        end

        # Closed here, so they can still be made unique before their turn.
        next_in_line = Na__NobleDrawingTools.Na__ScaleCommit__Settle(plan, node[:children], entities, target)
        opened       = {}
        node[:children].each { |child| opened[child[:live]] = true if child[:live] }

        parts.each do |part|
            next unless part.valid?
            next if opened[part]                                              # <-- Stretched from inside: its own turn, or its copy's

            part_local = inverse * part.transformation
            mins, _max = Na__NobleDrawingTools.Na__ScaleCommit__LocalBox(part.definition.bounds, part_local)
            part.transform!(world * Na__NobleDrawingTools.Na__ScaleField__Affine(field, mins) * inverse)
            tally[:rigid] += 1
        end

        next_in_line
    end
    # ---------------------------------------------------------------

    # FUNCTION | Move a Context's Vertices Where the Field Sends Them; Returns How Many
    # ------------------------------------------------------------
    # The context has to be open, so its vertices report global and
    # transform_by_vectors takes global: into the frame's axes through its
    # inverse, through the field, and back.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__MoveVertices(entities, vertices, frame, field)
        moved   = []
        vectors = []

        vertices.each_value do |vertex|
            reported = vertex.position
            goal     = Na__NobleDrawingTools.Na__ScaleField__MapPoint(field, reported.transform(frame[:inverse])).transform(frame[:world])
            vector   = goal - reported
            raise ArgumentError, 'a point would go to an impossible place' unless [vector.x, vector.y, vector.z].all? { |value| value.to_f.finite? }
            next if vector.length.to_f < NA_SCALE_MOVE_TOL

            moved   << vertex
            vectors << vector
        end

        unless moved.empty?
            chains = Na__NobleDrawingTools.Na__CurveUnweld__Explode(moved)       # <-- WELDED CURVES: re-fitted round the move unless exploded
            entities.transform_by_vectors(moved, vectors)
            Na__NobleDrawingTools.Na__CurveUnweld__Reweld(entities, chains)
        end

        moved.length
    end
    # ---------------------------------------------------------------

    # FUNCTION | Stretch Loose Geometry, or a Selection of Objects, in the Open Context
    # ------------------------------------------------------------
    # 5.2.22, 5.2.41. In three parts, one undo step:
    #
    #   1. In the user's own context, one operation: the loose points go
    #      through the field as an object's do (they report and take world
    #      there); every object no plane runs through, and every guide or
    #      text, is carried whole with its slice; every object a plane DOES
    #      run through is made unique if it is shared, closed, ready for its
    #      turn. next_transparent when an object is to be opened.
    #   2. Each object a plane runs through is opened and stretched from
    #      inside, by the single object's walk (Na__ScaleCommit__Walk), its
    #      own parts after it. The frame is the selection's: the open
    #      context's axes, so a point read inside goes to the frame through
    #      frame[:inverse] exactly as one read in the user's context does.
    #   3. The user's context is put back, which the last edit pulls in.
    #
    # The selection's own objects sit one below the user's context, so each
    # is to the walk what a part is to a single object: its own saved planes
    # move with its geometry (CarryPartPlanes). Refused if the user has since
    # moved to another context: the points are no longer in the one open.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__StretchLoose(model, frame, field)
        tally = { :unique => 0, :rigid => 0, :opened => 0, :moved => 0, :base => Na__NobleDrawingTools.Na__ScaleFrame__OpenDepth(model) }

        unless Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, frame[:context])
            return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, 'the open group changed since the geometry was taken — select it again', tally)
        end

        list = frame[:entities].select(&:valid?)
        return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, 'the geometry is no longer there', tally) if list.empty?

        failed = Na__NobleDrawingTools.Na__ScaleCommit__CheckRoomLoose(frame, field, list)
        return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, failed, tally) if failed

        vertices = {}
        carried  = []
        opened   = []

        list.each do |entity|
            if entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::Face)
                entity.vertices.each { |vertex| vertices[vertex.entityID] ||= vertex }
            elsif Na__NobleDrawingTools.Na__ScaleCommit__Instance?(entity) && !Na__NobleDrawingTools.Na__ScaleCommit__LooseRigid?(frame, field, entity)
                opened << entity
            else
                carried << entity
            end
        end

        # A locked object cannot be opened for editing: say so before anything
        # moves, rather than stop half way with the rest already stretched.
        locked = opened.find { |instance| instance.respond_to?(:locked?) && instance.locked? }
        if locked
            return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, "#{Na__NobleDrawingTools.Na__DeepPick__InstanceName(locked)} is locked and a plane runs through it — unlock it to stretch it", tally)
        end

        # On paper first (5.2.43): every object to be opened, and every part
        # inside one that a plane runs through, so copies that stretch alike
        # stay one definition and copies outside the stretch are kept apart.
        plan = Na__NobleDrawingTools.Na__ScaleCommit__PlanObjects(model, frame, field, opened)
        return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, plan[:refused], tally, plan) if plan[:refused]

        previous = model.active_path
        selected = Na__NobleDrawingTools.Na__DeepPick__FocusSnapshot(model)  # <-- Entering a context clears this
        pending  = false
        base     = Array(previous)
        queue    = []

        model.start_operation(NA_SCALE_OP_STRETCH, true, !opened.empty?, false) # <-- next_transparent: the first object's context entry joins this step

        begin
            entities        = model.active_entities
            tally[:moved]  += Na__NobleDrawingTools.Na__ScaleCommit__MoveVertices(entities, vertices, frame, field)

            carried.each do |entity|
                mins, maxs = Na__NobleDrawingTools.Na__ScaleCommit__LooseBox(frame, entity)
                middle     = (0..2).map { |n| (mins[n] + maxs[n]) * 0.5 }
                delta      = frame[:world] * Na__NobleDrawingTools.Na__ScaleField__Affine(field, middle) * frame[:inverse]
                entities.transform_entities(delta, [entity])
                tally[:rigid] += 1
            end

            # Closed here, so they can still be made unique before their turn:
            # stretching one copy of a window must not stretch every copy, and
            # copies selected together that stretch alike stay one component.
            queue = Na__NobleDrawingTools.Na__ScaleCommit__Settle(plan, plan[:roots], entities, base)

            model.commit_operation
            pending = !opened.empty?
        rescue StandardError => error
            model.abort_operation
            return Na__NobleDrawingTools.Na__ScaleCommit__Result(false, error.message, tally, plan)
        end

        return Na__NobleDrawingTools.Na__ScaleCommit__Result(true, nil, tally, plan) if opened.empty?

        objects         = opened.length                                   # <-- Every object opened, the ones riding on a copy's edit too
        riding          = plan[:roots].count { |node| node[:final] && !plan[:finals][node[:final]].equal?(node) }
        failed, pending = Na__NobleDrawingTools.Na__ScaleCommit__Walk(model, frame, field, queue, tally, pending, plan)

        restored = Na__NobleDrawingTools.Na__ScaleCommit__Restore(model, previous)
        Na__NobleDrawingTools.Na__ScaleCommit__ClosePending(model) if pending && !restored
        Na__NobleDrawingTools.Na__DeepPick__FocusRestore(model, selected)

        Na__NobleDrawingTools.Na__ScaleCommit__Result(failed.nil?, failed, tally, plan).merge(:objects => objects, :object_riders => riding)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This a Group or a Component?
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Instance?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is an Object in a Selection Carried Whole by This Field?
    # ------------------------------------------------------------
    # True when no plane runs through its own box, read in the frame's axes:
    # the same question a part inside a single object is asked. False sends
    # it to be opened and stretched from inside.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__LooseRigid?(frame, field, entity)
        mins, maxs = Na__NobleDrawingTools.Na__ScaleCommit__LooseBox(frame, entity)
        Na__NobleDrawingTools.Na__ScaleField__RigidOver?(field, mins, maxs)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Box of Something Carried Whole in a Loose Selection, in the Frame's Axes
    # ------------------------------------------------------------
    # Read from the open context, where a group's transformation reads as
    # world. Anything else, a guide or a text, reports its bounds in world.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__LooseBox(frame, entity)
        if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            return Na__NobleDrawingTools.Na__ScaleCommit__LocalBox(entity.definition.bounds, frame[:inverse] * entity.transformation)
        end

        Na__NobleDrawingTools.Na__ScaleCommit__LocalBox(entity.bounds, frame[:inverse])
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is There Room for This Shrink of Loose Geometry? nil If So, Else Why Not
    # ------------------------------------------------------------
    # An object a plane runs through is opened by the stretch, so its own
    # points count, read down through its parts as a single object's are
    # (5.2.41). The object is closed and reports local, and its
    # transformation reads world in the open context, so frame[:inverse]
    # times it takes its points to the frame.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__CheckRoomLoose(frame, field, list)
        return nil unless NA_SCALE_AXES.any? { |axis| field[axis][:mode] == :stretch && field[axis][:delta].to_f < 0.0 }

        coords = { :x => [], :y => [], :z => [] }

        list.each do |entity|
            if entity.is_a?(Sketchup::Edge) || entity.is_a?(Sketchup::Face)
                entity.vertices.each do |vertex|
                    point = vertex.position.transform(frame[:inverse])
                    NA_SCALE_AXES.each_with_index { |axis, n| coords[axis] << point[n].to_f }
                end
            elsif Na__NobleDrawingTools.Na__ScaleCommit__Instance?(entity) && !Na__NobleDrawingTools.Na__ScaleCommit__LooseRigid?(frame, field, entity)
                Na__NobleDrawingTools.Na__ScaleCommit__CollectCoords(entity.definition, frame[:inverse] * entity.transformation, field, coords, 1)
            else
                mins, maxs = Na__NobleDrawingTools.Na__ScaleCommit__LooseBox(frame, entity)
                NA_SCALE_AXES.each_with_index { |axis, n| coords[axis].push(mins[n], maxs[n]) }
            end
        end

        Na__NobleDrawingTools.Na__ScaleCommit__RoomFor(frame, field, coords)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is There Room for This Shrink? nil If So, Else Why Not
    # ------------------------------------------------------------
    # Read from the model before anything moves: every point of the object
    # and of each part a plane runs through, and both ends of each part
    # carried whole, in the object's own axes. The same arithmetic as the
    # drag limit (Na__ScaleField__StretchMinDelta), with the full geometry.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__CheckRoom(frame, field)
        return nil unless NA_SCALE_AXES.any? { |axis| field[axis][:mode] == :stretch && field[axis][:delta].to_f < 0.0 }

        coords = { :x => [], :y => [], :z => [] }
        Na__NobleDrawingTools.Na__ScaleCommit__CollectCoords(frame[:instance].definition, Geom::Transformation.new, field, coords, 0)
        Na__NobleDrawingTools.Na__ScaleCommit__RoomFor(frame, field, coords)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Given the Points, Is There Room? nil If So, Else Why Not
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__RoomFor(frame, field, coords)
        shrinking = NA_SCALE_AXES.select { |axis| field[axis][:mode] == :stretch && field[axis][:delta].to_f < 0.0 }

        shrinking.each do |axis|
            n     = NA_SCALE_AXIS_INDEX[axis]
            spec  = field[axis]
            keep  = NA_SCALE_MIN_GAP.to_f / frame[:scales][n]
            least = Na__NobleDrawingTools.Na__ScaleField__StretchMinDelta(spec[:planes], spec[:centre], frame[:local_lengths][n], coords[axis], keep)
            next if spec[:delta].to_f >= least - 1e-9

            floor = Na__NobleDrawingTools.Na__DrawnFormat__Mm((frame[:local_lengths][n] + least) * frame[:scales][n])
            return "#{axis.to_s.upcase} has no room to shrink that far — details either side of its planes would meet (#{floor} mm is as small as it goes)"
        end

        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Gather Point Coordinates, in the Object's Axes, Down Through Its Parts
    # ------------------------------------------------------------
    # The object sits below the user's context, so it and everything inside
    # it is closed and reports its own local space: a part's transformation
    # is relative to its parent, and to_object carries each level up.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__CollectCoords(definition, to_object, field, coords, depth)
        definition.entities.each do |entity|
            if entity.is_a?(Sketchup::Edge)
                entity.vertices.each do |vertex|
                    point = vertex.position.transform(to_object)
                    coords[:x] << point.x.to_f
                    coords[:y] << point.y.to_f
                    coords[:z] << point.z.to_f
                end
            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                part_local = to_object * entity.transformation
                mins, maxs = Na__NobleDrawingTools.Na__ScaleCommit__LocalBox(entity.definition.bounds, part_local)

                if Na__NobleDrawingTools.Na__ScaleField__RigidOver?(field, mins, maxs) || depth + 1 > NA_SCALE_MAX_DEPTH
                    NA_SCALE_AXES.each_with_index { |axis, n| coords[axis].push(mins[n], maxs[n]) }
                else
                    Na__NobleDrawingTools.Na__ScaleCommit__CollectCoords(entity.definition, part_local, field, coords, depth + 1)
                end
            end
        end

        coords
    end
    # ---------------------------------------------------------------

    # FUNCTION | Make an Instance Unique and Carry Its Stretch Planes Across
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__MakeUnique(instance)
        before = instance.definition
        planes = Na__NobleDrawingTools.Na__ScalePlanes__Read(before)

        instance.make_unique

        after = instance.definition
        Na__NobleDrawingTools.Na__ScalePlanes__Write(after, planes) if !after.equal?(before) && Na__NobleDrawingTools.Na__ScalePlanes__Total(planes) > 0
        after
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Stretched Part's Own Planes Move With Its Geometry
    # ------------------------------------------------------------
    # A part carried whole keeps its planes as they are: they are in its own
    # axes, and its axes moved with it. A part that was opened and stretched
    # had its points moved inside its own axes, so its planes have to move
    # the same way or they would be left cutting the wrong place. Each is
    # taken out to the object's axes, through the field, and back.
    #
    # Only along a part axis that lines up with one of the object's: a plane
    # square to a part turned at an angle would be sheared by the stretch,
    # and no plane can say that. Those are left where they were.
    #
    # Called from inside the part's own context, so its box is not read here
    # (an open definition's geometry reports global). None is needed: the
    # field keeps order, so a plane inside the part before is inside after,
    # and an orphan it already had is dropped at its next write as ever.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__CarryPartPlanes(part, part_local, field)
        definition = part.definition
        planes     = Na__NobleDrawingTools.Na__ScalePlanes__Read(definition)
        return false if Na__NobleDrawingTools.Na__ScalePlanes__Total(planes).zero?

        units = [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1)]
        moved = Na__NobleDrawingTools.Na__ScalePlanes__Empty

        NA_SCALE_AXES.each_with_index do |axis, n|
            list = planes[axis]
            next if list.empty?

            along  = Na__NobleDrawingTools.Na__ScaleFrame__WorldVector(part_local, units[n])
            length = along.length.to_f
            target = (0..2).find { |index| length > 0.0 && (along[index].abs / length) > 0.9999 }

            unless target
                moved[axis] = list.dup
                next
            end

            moved[axis] = list.map do |value|
                spot       = Geom::Point3d.new(n.zero? ? value : 0.0, n == 1 ? value : 0.0, n == 2 ? value : 0.0).transform(part_local)
                carried    = Na__NobleDrawingTools.Na__ScaleField__Value(field[NA_SCALE_AXES[target]], spot[target])
                value + ((carried - spot[target]) / along[target])
            end
        end

        Na__NobleDrawingTools.Na__ScalePlanes__Write(definition, moved)
    rescue StandardError => error
        Na__NobleDrawingTools.Na__Debug__Puts "NA DEEP SCALE: a part's planes were not carried — #{error.message}"
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Part's Box in the Object's Own Axes, as [mins, maxs]
    # The eight corners transformed, so a part turned inside the object is
    # judged by the room it really takes up along each axis.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__LocalBox(bounds, xform)
        return [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]] if bounds.nil? || bounds.empty?

        corners = (0..7).map { |index| bounds.corner(index).transform(xform) }
        mins    = (0..2).map { |n| corners.map { |point| point[n].to_f }.min }
        maxs    = (0..2).map { |n| corners.map { |point| point[n].to_f }.max }

        [mins, maxs]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Shared Copies — the Stretch on Paper (5.2.43)
    # -----------------------------------------------------------------------------

    # FUNCTION | Plan One Object's Stretch; Returns [plan, the object's node]
    # ------------------------------------------------------------
    # `path` is absolute. The instances between the user's context and the
    # object are containers (:via): they change only because something in
    # them does, and are settled first so a shared one never carries the
    # stretch to its other copies. The object and every part the walk will
    # open are :target nodes. A node's world is the product of the
    # transformations down from the user's context: the first reads world
    # there, the rest local to their parents (note 02).
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__PlanObject(model, frame, field, path)
        plan   = Na__NobleDrawingTools.Na__DeepUnique__NewPlan(model)
        below  = path[Na__NobleDrawingTools.Na__ScaleFrame__OpenDepth(model)..-1] || []
        below  = [frame[:instance]] if below.empty?
        parent = nil
        world  = nil

        below[0...-1].each do |instance|
            world  = world ? world * instance.transformation : instance.transformation
            parent = Na__NobleDrawingTools.Na__DeepUnique__AddNode(plan, instance, parent, world, { :role => :via })
        end

        object = Na__NobleDrawingTools.Na__DeepUnique__AddNode(
            plan, below.last, parent, frame[:world],
            { :role => :target, :to_frame => Geom::Transformation.new, :depth => 0 }
        )

        Na__NobleDrawingTools.Na__ScaleCommit__PlanParts(plan, object, frame, field)
        Na__NobleDrawingTools.Na__ScaleCommit__Sign(plan, field)
        Na__NobleDrawingTools.Na__DeepUnique__Decide(plan)
        [plan, object]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Plan a Selection's Stretch: Every Object a Plane Runs Through
    # ------------------------------------------------------------
    # The objects stand in the user's own context, where their
    # transformations read world; frame[:inverse] takes them into the
    # selection's axes.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__PlanObjects(model, frame, field, instances)
        plan = Na__NobleDrawingTools.Na__DeepUnique__NewPlan(model)

        instances.each do |instance|
            world = instance.transformation
            node  = Na__NobleDrawingTools.Na__DeepUnique__AddNode(
                plan, instance, nil, world,
                { :role => :target, :to_frame => frame[:inverse] * world, :depth => 1 }
            )
            Na__NobleDrawingTools.Na__ScaleCommit__PlanParts(plan, node, frame, field)
        end

        Na__NobleDrawingTools.Na__ScaleCommit__Sign(plan, field)
        Na__NobleDrawingTools.Na__DeepUnique__Decide(plan)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Parts Inside a Node That a Plane Runs Through, as Nodes
    # ------------------------------------------------------------
    # The walk's own test (StretchContext before 5.2.43): a part whose box,
    # in the frame's axes, sits inside one slice on every stretching axis is
    # carried whole; past the depth guard everything is carried. Below the
    # user's context every definition is closed, so a part's transformation
    # is local to its parent and to_frame carries each level up.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__PlanParts(plan, node, frame, field)
        depth    = node[:payload][:depth]
        to_frame = node[:payload][:to_frame]
        return if depth + 1 > NA_SCALE_MAX_DEPTH

        node[:definition].entities.each do |entity|
            next unless Na__NobleDrawingTools.Na__ScaleCommit__Instance?(entity)

            part_frame = to_frame * entity.transformation
            mins, maxs = Na__NobleDrawingTools.Na__ScaleCommit__LocalBox(entity.definition.bounds, part_frame)
            next if Na__NobleDrawingTools.Na__ScaleField__RigidOver?(field, mins, maxs)

            child = Na__NobleDrawingTools.Na__DeepUnique__AddNode(
                plan, entity, node, frame[:world] * part_frame,
                { :role => :target, :to_frame => part_frame, :depth => depth + 1 }
            )
            Na__NobleDrawingTools.Na__ScaleCommit__PlanParts(plan, child, frame, field)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sign Every Node: Where the Field Sends Each of Its Points
    # ------------------------------------------------------------
    # Read in the node's own axes: every vertex of its definition and of
    # everything inside it, mapped to the frame, through the field and back.
    # Two copies whose points all land alike want exactly the same edit —
    # the same vertices moved, the same parts carried or opened — so they
    # can share. Only worked out where two nodes share a definition; a
    # container signs with what is below it.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Sign(plan, field)
        points = {}
        plan[:roots].each { |root| Na__NobleDrawingTools.Na__ScaleCommit__SignNode(plan, root, field, points) }
        plan
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sign One Node, Its Children First
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__SignNode(plan, node, field, points)
        node[:children].each { |child| Na__NobleDrawingTools.Na__ScaleCommit__SignNode(plan, child, field, points) }

        if node[:payload][:role] == :via
            node[:signature] = [:via, node[:children].map { |child| [child[:instance].entityID, child[:signature]] }]
            return
        end

        unless Na__NobleDrawingTools.Na__DeepUnique__Shared?(plan, node)
            node[:signature] = [:one]                                         # <-- Nothing to compare it with
            return
        end

        unless points.key?(node[:definition])
            points[node[:definition]] = Na__NobleDrawingTools.Na__ScaleCommit__SubtreePoints(plan, node[:definition])
        end

        list = points[node[:definition]]

        unless list && Na__NobleDrawingTools.Na__DeepUnique__Spend(plan, list.length)
            node[:signature] = Na__NobleDrawingTools.Na__DeepUnique__Alone(node)   # <-- Too big to compare: it parts, as before 5.2.43
            return
        end

        to_frame = node[:payload][:to_frame]
        back     = to_frame.inverse

        node[:signature] = list.map do |point|
            goal = Na__NobleDrawingTools.Na__ScaleField__MapPoint(field, point.transform(to_frame)).transform(back)
            Na__NobleDrawingTools.Na__DeepUnique__Quantise(goal - point)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Point of a Definition and Everything Inside It, in Its Axes
    # ------------------------------------------------------------
    # In a fixed order, so the lists of two copies compare point for point.
    # nil when there are more than the signing budget has left.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__SubtreePoints(plan, definition)
        room   = NA_DEEP_UNIQUE_MAX_WORK - plan[:work]
        points = []
        return nil unless Na__NobleDrawingTools.Na__ScaleCommit__GatherPoints(definition, Geom::Transformation.new, points, 0, room)

        points
    end
    # ---------------------------------------------------------------

    # FUNCTION | Gather Points Down Through a Definition; False Past the Cap
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__GatherPoints(definition, xform, points, depth, cap)
        seen = {}

        definition.entities.each do |entity|
            if entity.is_a?(Sketchup::Edge)
                entity.vertices.each do |vertex|
                    next if seen[vertex.entityID]

                    seen[vertex.entityID] = true
                    points << vertex.position.transform(xform)
                end
            elsif Na__NobleDrawingTools.Na__ScaleCommit__Instance?(entity) && depth < NA_SCALE_MAX_DEPTH
                return false unless Na__NobleDrawingTools.Na__ScaleCommit__GatherPoints(entity.definition, xform * entity.transformation, points, depth + 1, cap)
            end

            return false if points.length > cap
        end

        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Settle Planned Copies in a Collection; Returns [path, node] Pairs
    # ------------------------------------------------------------
    # Na__DeepUnique__SettleIn with Deep Scale's planes carried across every
    # make_unique, and each representative's path made from its container's.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Settle(plan, nodes, entities, base)
        reps = Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, nodes, entities, Na__NobleDrawingTools.Na__ScaleCommit__PlanesHook)
        reps.map { |rep| [base + [rep[:live]], rep] }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Carry a Definition's Stretch Planes to Its Unique Copy
    # ------------------------------------------------------------
    # The make_unique hook: the copy must still know where it stretches.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__PlanesHook
        lambda do |before, after|
            planes = Na__NobleDrawingTools.Na__ScalePlanes__Read(before)
            Na__NobleDrawingTools.Na__ScalePlanes__Write(after, planes) if !after.equal?(before) && Na__NobleDrawingTools.Na__ScalePlanes__Total(planes) > 0
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Saving Planes
    # -----------------------------------------------------------------------------

    # FUNCTION | Save a Plane Set on the Object as Its Own Undo Step
    # ------------------------------------------------------------
    # A plane is a decision about the object, so placing one is undoable like
    # anything else: Ctrl+Z takes back the last plane. No context is opened —
    # an attribute is not geometry and has no display cache to go stale.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__SavePlanes(model, definition, planes, op_name = NA_SCALE_OP_PLANE)
        return false unless model && definition && definition.valid?

        model.start_operation(op_name, true)

        begin
            Na__NobleDrawingTools.Na__ScalePlanes__Write(definition, planes)
            model.commit_operation
            true
        rescue StandardError => error
            model.abort_operation
            Na__NobleDrawingTools.Na__Debug__Puts "NA DEEP SCALE: #{op_name} failed — #{error.message}"
            false
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP SCALE COMMIT
# =============================================================================
