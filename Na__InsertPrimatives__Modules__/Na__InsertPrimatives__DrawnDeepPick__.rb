# =============================================================================
# NA INSERT PRIMATIVES - DEEP NESTED FACE PICKING
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnDeepPick__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Pick a face at any nesting depth, with the transformation maths
#              needed to push it without entering its group or component
# CREATED    : 2026
#
# DESCRIPTION:
# - Native Push/Pull only sees faces in the current editing context: to reach a
#   face inside a group you must double-click your way in first. PickHelper's
#   leaf_at / transformation_at pair hands back the deepest face under the
#   cursor together with the accumulated transformation to world space, which is
#   all that is needed to work on it in place.
#
# THE TWO COORDINATE SPACES:
# - A face lives in its own definition's local space. Its normal, its vertices
#   and the distance argument to pushpull are all local. The cursor and every
#   preview are world. transformation_at bridges the two.
# - A scaled instance makes those two disagree on distance. Transforming the
#   unit local normal gives a vector whose LENGTH is the scale factor along that
#   direction, so a world push distance divided by it is the local distance
#   pushpull actually wants. Skip that and a push inside a scaled component
#   overshoots by exactly the scale factor.
#
# THE SELECTION IS AN INSTRUCTION, NOT DECORATION:
# - Picking by proximity is a guess about which group was meant, and it is only
#   a good one while the user has not said. A selected group says it, so a pick
#   whose path runs through the current selection is taken ahead of everything
#   else under the cursor. Nothing selected, nothing changes - the guess stands
#   exactly as it did. It is read fresh on every hover and never remembered,
#   so deselecting drops the bias the same frame.
#
# EDITING IN PLACE IS SHARED EDITING:
# - Pushing a face inside a definition used more than once changes every
#   instance. That is correct SketchUp behaviour and not something to silently
#   work around, so the instance count is reported and the caller warns.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Picking Constants
    # -----------------------------------------------------------------------------

    NA_DEEP_PICK_MAX_PATHS = 32                                               # <-- Depth guard on a crowded pick
    NA_DEEP_PICK_SPACE_TOL = 0.002                                            # <-- Inches; twice SketchUp's own 0.001" merge tolerance
    NA_DEEP_PICK_FOCUS_MAX = 512                                              # <-- Above this a selection states no preference; see FocusSet

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Selection Focus
    # -----------------------------------------------------------------------------

    # FUNCTION | The Groups and Components the User Has Selected
    # ------------------------------------------------------------
    # THE PROBLEM THIS SOLVES:
    # - Deep picking reaches into whichever group happens to sit closest under
    #   the cursor. That is the right guess while the user has not said which
    #   group they mean, and the wrong one the moment they have: a face of the
    #   neighbouring group gets grabbed because it sat a millimetre nearer the
    #   camera than the one that was wanted.
    # - So the user's own selection is read as a statement of intent - "work on
    #   THIS one, leave the rest of the model alone until I deselect it". No
    #   selection means no statement, and the pick guesses exactly as before.
    #
    # WHY ONLY GROUPS AND COMPONENTS ARE COLLECTED:
    # - The question the bias answers is WHICH CONTAINER did you mean. A
    #   selected loose face needs no bias: the open-context rule below already
    #   hands it the pick. Collecting containers only also means a selection
    #   that contains no group at all - a few loose faces, a stray edge - states
    #   nothing about containers and correctly changes nothing.
    #
    # WHY THIS IS REBUILT EVERY HOVER AND NEVER CACHED:
    # - A cache needs invalidating, SketchUp offers no selection version to
    #   invalidate against, and SelectionObserver is known to miss changes. A
    #   stale focus would keep favouring the group the user just deselected -
    #   precisely the bug this feature exists to prevent, and one that would be
    #   blamed on the tool rather than on the cache.
    # - Rebuilding costs nothing for the handful of groups a focus actually
    #   means. The only thing worth guarding is Ctrl+A: a selection that size
    #   expresses no preference at all, so it is dropped rather than walked on
    #   every frame. #length is the native O(1) count, so the guard is free.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FocusInstances
        model = Sketchup.active_model
        return [] unless model

        selection = model.selection
        return [] unless selection

        count = selection.length.to_i
        return [] if count < 1 || count > NA_DEEP_PICK_FOCUS_MAX

        # to_a first, deliberately. Enumerable#select would work, but Selection
        # is a SketchUp collection whose own vocabulary is all about selecting,
        # and an array is unambiguous about which #select this is.
        selection.to_a.select do |entity|
            entity && entity.valid? &&
                (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
        end
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | That Same Focus as a Fast Lookup - or nil
    # entityID keys rather than the entities themselves: an O(1) lookup that
    # holds no references, so a group erased between one mouse move and the
    # next cannot strand a dead Sketchup::Entity in here.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FocusSet
        instances = Na__InsertPrimatives.Na__DeepPick__FocusInstances
        return nil if instances.empty?

        focus = {}
        instances.each { |instance| focus[instance.entityID] = true }
        focus
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does This Pick Lie Inside What the User Selected?
    # ANY instance on the path counts, not just the innermost one: selecting a
    # group claims every face and edge inside it, at any depth below it,
    # without the user ever opening it - which is the whole point of a tool
    # that can already reach in there.
    # ------------------------------------------------------------
    def self.Na__DeepPick__InFocus?(path, focus)
        return false unless focus

        Na__InsertPrimatives.Na__DeepPick__Instances(path).any? do |instance|
            focus[instance.entityID]
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | First Pick Under the Cursor That Belongs to the Focus
    # ------------------------------------------------------------
    # The same shallowest-first walk the ordinary scan uses, so among the faces
    # of the focused group the one nearest the camera still wins: the bias
    # chooses the GROUP, it does not re-order what is inside it. Locked
    # geometry stays invisible here too, exactly as it is everywhere else.
    #
    # nil when nothing under the cursor belongs to the focus - which is what
    # sends the caller back to the ordinary passes. That fallback is deliberate:
    # the selection is a BIAS, not a lock. Hovering a group the user did not
    # select still picks it, so the tool never reads as broken.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FocusedPickAt(helper, focus, kind)
        count = helper.count.to_i
        limit = count < NA_DEEP_PICK_MAX_PATHS ? count : NA_DEEP_PICK_MAX_PATHS
        index = 0

        while index < limit
            leaf = helper.leaf_at(index)

            if leaf.is_a?(kind)
                path = helper.path_at(index)

                # The focus test runs BEFORE the target is built: it is a hash
                # lookup, while building a target counts shared instances and
                # transforms a normal. On a crowded pick that is most of the
                # per-frame cost avoided.
                if Na__InsertPrimatives.Na__DeepPick__InFocus?(path, focus)
                    xform  = helper.transformation_at(index)
                    target =
                        if kind == Sketchup::Face
                            Na__InsertPrimatives.Na__DeepPick__BuildTarget(leaf, path, xform)
                        else
                            Na__InsertPrimatives.Na__DeepPick__BuildEdgeTarget(leaf, path, xform)
                        end

                    return target unless Na__InsertPrimatives.Na__DeepPick__LockedOut?(leaf, target)
                end
            end

            index += 1
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Focus Stand Down for This Loose Pick?
    # ------------------------------------------------------------
    # The focus outranks the loose-geometry safeguard, with one exception: when
    # the loose thing under the cursor is ITSELF selected, the safeguard's
    # answer and the selection's answer are the same answer, so there is
    # nothing to arbitrate and the ordinary pass keeps it.
    #
    # That exception is what makes Ctrl+A harmless. With everything selected
    # the focus contains every group in the model and would otherwise favour
    # the nearest of them over the loose face sitting in front of it - a bias
    # in a case where the user expressed no preference at all. Everything
    # selected also means the loose face is selected, so this stands the focus
    # down and the safeguard behaves exactly as it always did.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FocusYieldsTo?(entity)
        return false unless entity
        return false unless Na__InsertPrimatives.Na__DeepPick__InOpenContext?(entity)

        model = Sketchup.active_model
        return false unless model

        selection = model.selection
        return false unless selection

        selection.include?(entity)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Short Name for Whatever the Focus Is, or nil
    # Read by the tools' status lines, so a changed picking rule is visible
    # rather than mysterious. It follows the same cap as the focus itself, so
    # the status bar can never claim a bias the picker is not applying.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FocusLabel
        instances = Na__InsertPrimatives.Na__DeepPick__FocusInstances
        return nil if instances.empty?
        return "#{instances.length} selected" if instances.length > 1

        instance = instances.first
        name     = ''

        begin
            name = instance.name.to_s
            name = instance.definition.name.to_s if name.empty? && instance.respond_to?(:definition)
        rescue StandardError
            name = ''
        end

        name.empty? ? '1 selected' : name
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remember the Selection Before a Context Change Eats It
    # ------------------------------------------------------------
    # Opening a group's editing context clears the selection, the same way
    # double-clicking into one does by hand. Left alone that would undo the
    # focus on the very first commit: the user selects a group, pushes one face
    # of it, and the tool is back to guessing for the next face - with nothing
    # on screen to explain why. So the selection is taken before the context is
    # entered and put back once it has been restored.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FocusSnapshot(model)
        return [] unless model

        selection = model.selection
        return [] unless selection

        count = selection.length.to_i
        return [] if count < 1 || count > NA_DEEP_PICK_FOCUS_MAX

        selection.to_a
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put That Selection Back, but Only If Something Took It
    # ------------------------------------------------------------
    # Restoring over a selection made since the snapshot would be a worse bug
    # than the one being fixed, so this only ever refills an EMPTY selection,
    # and only with entities that survived the edit. A push that consumed the
    # group it was working on therefore leaves nothing selected, which is the
    # honest answer.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FocusRestore(model, snapshot)
        return false unless model
        return false unless snapshot.is_a?(Array) && !snapshot.empty?

        selection = model.selection
        return false unless selection
        return false unless selection.length.to_i.zero?

        alive = snapshot.select { |entity| entity && entity.valid? }
        return false if alive.empty?

        selection.add(alive)
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Face Picking
    # -----------------------------------------------------------------------------

    # FUNCTION | Find the Face Under the Cursor, Shallowest First
    # Returns a hash carrying the face, its instance path, the transformation to
    # world space and the scale factor along its normal — or nil when the cursor
    # is not over a face.
    #
    # WHAT THE USER SELECTED OUTRANKS EVERY GUESS BELOW IT:
    # - The two rules further down are guesses about which face was meant, and
    #   they are good ones only while the user has not said. A selection says
    #   it: "this group, not the others, until I deselect it". So a selected
    #   group is checked FIRST, ahead of even the loose-geometry safeguard,
    #   because a decision beats a safeguard against accidents that this user
    #   has explicitly stopped having.
    # - It is a bias and not a lock. Nothing of the selection under the cursor
    #   and the ordinary passes run untouched, so hovering some other group
    #   still picks that group rather than refusing.
    # - The one thing that stands the bias down is a loose pick that is itself
    #   selected: see Na__DeepPick__FocusYieldsTo?.
    #
    # LOOSE GEOMETRY WINS, AND THAT IS A SAFEGUARD NOT A PREFERENCE:
    # - Reaching into a group without opening it is this tool's whole point, and
    #   it is also the way to wreck a model by accident while drafting. So when
    #   a face sits in the context the user actually has OPEN — loose in the
    #   model root, or loose inside the group they are already editing — that
    #   face is taken and the nested ones are not even considered.
    # - Only when nothing is in the open context does the pick reach inside.
    #
    # WHY picked_face IS CONSULTED AS WELL AS leaf_at:
    # - leaf_at / path_at walk INSTANCE PATHS. A face lying loose in the open
    #   context has no instance path to walk, so it can be absent from that list
    #   entirely — which is why loose faces could not be pushed at all.
    #   PickHelper#picked_face is the route that reports it, so it is asked
    #   first and the path scan is the fallback rather than the other way round.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FaceAt(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)

        direct = helper.picked_face

        # PASS 0 — the group the user has SELECTED, when they have selected one.
        focus = Na__InsertPrimatives.Na__DeepPick__FocusSet
        if focus && !Na__InsertPrimatives.Na__DeepPick__FocusYieldsTo?(direct)
            focused = Na__InsertPrimatives.Na__DeepPick__FocusedPickAt(helper, focus, Sketchup::Face)
            return focused if focused
        end

        # PASS 1 — a face in the open editing context, by the one route that
        # reports loose geometry. The context guard is not optional: if
        # picked_face ever hands back something nested, taking it unchecked
        # would kill deep picking outright, which is the tool's whole reason to
        # exist. Nested faces fall through to the path scan below.
        #
        # The path and transform come from the OPEN CONTEXT, not from nil.
        # Inside a group the user has opened, its geometry is "loose" to them
        # but is still nested to the model: handing back nil there would report
        # depth zero, use the local normal as if it were the world one, and send
        # the commit to close the user's own context before pushing. At root
        # both are the identity anyway, so loose geometry is unaffected.
        if direct.is_a?(Sketchup::Face) && Na__InsertPrimatives.Na__DeepPick__InOpenContext?(direct)
            target = Na__InsertPrimatives.Na__DeepPick__BuildTarget(
                direct,
                Na__InsertPrimatives.Na__DeepPick__ContextPath,
                Na__InsertPrimatives.Na__DeepPick__ContextTransform
            )
            return target unless Na__InsertPrimatives.Na__DeepPick__LockedOut?(direct, target)
        end

        depth  = Na__InsertPrimatives.Na__DeepPick__ContextDepth
        count  = helper.count.to_i
        limit  = count < NA_DEEP_PICK_MAX_PATHS ? count : NA_DEEP_PICK_MAX_PATHS
        nested = nil
        index  = 0

        while index < limit
            leaf = helper.leaf_at(index)

            if leaf.is_a?(Sketchup::Face)
                target = Na__InsertPrimatives.Na__DeepPick__BuildTarget(
                    leaf, helper.path_at(index), helper.transformation_at(index)
                )

                # Locked geometry is not merely refused, it is not seen at all:
                # no hover, no target, no push. The scan carries on past it, so
                # a locked group is transparent to whatever stands behind it.
                if Na__InsertPrimatives.Na__DeepPick__LockedOut?(leaf, target)
                    index += 1
                    next
                end

                # PASS 2 — still in the open context, just reached the long way.
                return target if target[:depth] == depth

                nested = target if nested.nil?                                # <-- Deepest-first order preserved
            end

            index += 1
        end

        nested
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does This Entity Live Directly in the Context the User Has Open?
    # Compared through Entities#parent — a ComponentDefinition compares as an
    # entity, and a face whose parent is a Model is by definition loose in the
    # model root, so the two Model cases can be matched on type.
    # ------------------------------------------------------------
    def self.Na__DeepPick__InOpenContext?(entity)
        return false unless entity && entity.valid?

        model = Sketchup.active_model
        return false unless model

        context = model.active_entities
        return false unless context && context.respond_to?(:parent)

        parent = entity.parent
        owner  = context.parent
        return false unless parent && owner
        return true if parent.is_a?(Sketchup::Model) && owner.is_a?(Sketchup::Model)

        parent == owner
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Instance Path of the Context the User Has Open
    # nil at the model root, which is exactly what every path helper here
    # already treats as "no instances".
    # ------------------------------------------------------------
    def self.Na__DeepPick__ContextPath
        model = Sketchup.active_model
        return nil unless model && model.respond_to?(:active_path)

        path = model.active_path
        path.nil? ? nil : path.to_a
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | World Transform of the Context the User Has Open
    # The identity at root, so loose geometry needs no special case.
    # ------------------------------------------------------------
    def self.Na__DeepPick__ContextTransform
        model = Sketchup.active_model
        return nil unless model && model.respond_to?(:edit_transform)

        model.edit_transform
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Instances Deep the User's Open Context Is
    # Zero at the model root, so "loose geometry" and "the geometry of the group
    # I have open" are the same test and neither needs special-casing.
    # ------------------------------------------------------------
    def self.Na__DeepPick__ContextDepth
        Na__InsertPrimatives.Na__DeepPick__NestingDepth(
            Na__InsertPrimatives.Na__DeepPick__ContextPath
        )
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Pick Locked, and Therefore Not There at All?
    # ------------------------------------------------------------
    # Locked means INVISIBLE TO THE TOOL, not "refused on click". A refusal
    # still highlights the face, still puts a target under the cursor and still
    # beeps at you for asking — which is noise when the whole reason a thing is
    # locked is that you have decided to stop touching it. Skipped instead, a
    # locked group is transparent: the pick carries straight on to whatever
    # stands behind it, which is the geometry you could actually edit anyway.
    #
    # Both halves are checked. The path covers the normal case — a locked group
    # or component anywhere above the entity. The entity's own flag covers a
    # drawing element locked directly, which the UI does not offer but the API
    # does, and which would otherwise slip through at depth zero.
    # ------------------------------------------------------------
    def self.Na__DeepPick__LockedOut?(entity, target)
        return true if target && target[:locked]
        return true if entity && entity.respond_to?(:locked?) && entity.locked?

        false
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Assemble Everything the Push Tool Needs About a Face
    # ------------------------------------------------------------
    def self.Na__DeepPick__BuildTarget(face, path, transformation)
        xform        = transformation || Geom::Transformation.new
        world_normal = face.normal.transform(xform)
        scale        = world_normal.length.to_f
        scale        = 1.0 if scale <= 0.0

        {
            :face           => face,
            :path           => path,
            :transformation => xform,
            :world_normal   => world_normal.normalize,
            :normal_scale   => scale,                                         # <-- World distance / this = local distance
            :locked         => Na__InsertPrimatives.Na__DeepPick__PathLocked?(path),
            :depth          => Na__InsertPrimatives.Na__DeepPick__NestingDepth(path),
            :shared_count   => Na__InsertPrimatives.Na__DeepPick__SharedInstanceCount(path)
        }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Edge Picking
    # -----------------------------------------------------------------------------

    # FUNCTION | Find the Deepest Edge Under the Cursor
    # Same scan as Na__DeepPick__FaceAt and in the same order, hunting an Edge:
    # the user's selection first, then the open editing context, then the
    # nearest nested edge. Returns a target hash or nil when the cursor is not
    # over an edge.
    # ------------------------------------------------------------
    def self.Na__DeepPick__EdgeAt(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)

        direct = helper.picked_edge

        # PASS 0 — the group the user has SELECTED, when they have selected one.
        focus = Na__InsertPrimatives.Na__DeepPick__FocusSet
        if focus && !Na__InsertPrimatives.Na__DeepPick__FocusYieldsTo?(direct)
            focused = Na__InsertPrimatives.Na__DeepPick__FocusedPickAt(helper, focus, Sketchup::Edge)
            return focused if focused
        end

        # Loose edges are missed by a path scan for the same reason loose faces
        # are — no instance path to walk — and they win for the same safeguard.
        if direct.is_a?(Sketchup::Edge) && Na__InsertPrimatives.Na__DeepPick__InOpenContext?(direct)
            target = Na__InsertPrimatives.Na__DeepPick__BuildEdgeTarget(
                direct,
                Na__InsertPrimatives.Na__DeepPick__ContextPath,
                Na__InsertPrimatives.Na__DeepPick__ContextTransform
            )
            return target unless Na__InsertPrimatives.Na__DeepPick__LockedOut?(direct, target)
        end

        depth  = Na__InsertPrimatives.Na__DeepPick__ContextDepth
        count  = helper.count.to_i
        limit  = count < NA_DEEP_PICK_MAX_PATHS ? count : NA_DEEP_PICK_MAX_PATHS
        nested = nil
        index  = 0

        while index < limit
            leaf = helper.leaf_at(index)

            if leaf.is_a?(Sketchup::Edge)
                target = Na__InsertPrimatives.Na__DeepPick__BuildEdgeTarget(
                    leaf, helper.path_at(index), helper.transformation_at(index)
                )

                if Na__InsertPrimatives.Na__DeepPick__LockedOut?(leaf, target)
                    index += 1
                    next
                end

                return target if target[:depth] == depth

                nested = target if nested.nil?
            end

            index += 1
        end

        nested
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Assemble Everything the Chamfer Tool Needs About an Edge
    # face_count is carried so the caller can refuse edges that do not border
    # exactly two faces — the only configuration a chamfer is defined for.
    # ------------------------------------------------------------
    def self.Na__DeepPick__BuildEdgeTarget(edge, path, transformation)
        xform = transformation || Geom::Transformation.new
        faces = edge.faces

        {
            :edge           => edge,
            :faces          => faces,
            :face_count     => faces.length,
            :path           => path,
            :transformation => xform,
            :locked         => Na__InsertPrimatives.Na__DeepPick__PathLocked?(path),
            :depth          => Na__InsertPrimatives.Na__DeepPick__NestingDepth(path),
            :shared_count   => Na__InsertPrimatives.Na__DeepPick__SharedInstanceCount(path)
        }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Context-Managed Operations
    # -----------------------------------------------------------------------------

    # FUNCTION | Run a Model Edit Inside the Target's Own Editing Context
    # The lesson the push/pull saga was paid for: editing a definition's entities
    # from OUTSIDE its editing context leaves the model changed but the display
    # cache stale. This enters the context via model.active_path= (SketchUp
    # 2020+), runs the block inside one operation, then restores whatever context
    # the user was in — falling back to root rather than ever stranding them.
    #
    # Undo chaining mirrors the push tool exactly: when a context was entered the
    # operation starts (name, true, true, true) so enter-edit-restore unwinds as
    # ONE Ctrl+Z. The flags are strictly conditional — without a context change
    # they would merge the edit into whatever the user did last.
    #
    # Returns { :success, :error, :entered }.
    # ------------------------------------------------------------
    def self.Na__DeepPick__ExecuteInContext(model, path, op_name)
        instances   = Na__InsertPrimatives.Na__DeepPick__Instances(path)
        target_path = instances.empty? ? nil : instances
        entered     = false
        previous    = nil
        selected    = Na__InsertPrimatives.Na__DeepPick__FocusSnapshot(model)   # <-- Entering a context clears this
        result      = { :success => false, :error => nil, :entered => false }

        if model.respond_to?(:active_path=)
            begin
                previous = model.active_path                                  # <-- nil at root, else the user's context
                same     = (previous.nil? && target_path.nil?) ||
                           (!previous.nil? && !target_path.nil? && previous.to_a == target_path.to_a)

                unless same
                    model.active_path = target_path
                    entered = true
                end
            rescue StandardError
                entered = false                                               # <-- Fall through to an outside-context edit
            end
        end

        if entered
            model.start_operation(op_name, true, true, true)
        else
            model.start_operation(op_name, true)
        end

        begin
            yield
            Na__InsertPrimatives.Na__DeepPick__InvalidateDefinitions(path) unless entered
            model.commit_operation
            result[:success] = true
        rescue StandardError => error
            model.abort_operation
            result[:error] = error.message
        end

        if entered
            begin
                model.active_path = previous
            rescue StandardError
                begin
                    model.active_path = nil
                rescue StandardError
                    nil
                end
            end

            Na__InsertPrimatives.Na__DeepPick__FocusRestore(model, selected)  # <-- The focus survives the edit
        end

        result[:entered] = entered
        result
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Space an Entities Collection Wants New Points In
    # ------------------------------------------------------------
    # Returns the transformation to apply to DEFINITION-LOCAL points before
    # handing them to entities.add_*. The identity when the collection takes
    # local coordinates; Model#edit_transform when an open editing session has
    # moved the goalposts.
    #
    # WHY THIS IS MEASURED AND NOT ASSUMED:
    # - "When changing the active entities in SketchUp, the coordinate system
    #   also changes" is documented, but WHICH way it changes for a given
    #   collection is not, and guessing it wrong is silent: the geometry is
    #   created, it just lands somewhere else. That cost v0.4.22-v0.4.24 of the
    #   chamfer tool three releases to track down.
    # - So it is probed instead. A construction point is inert, costs nothing,
    #   and is added and erased inside the caller's own operation — invisible in
    #   the undo stack. Reading its position back says exactly how the
    #   collection read the input: unchanged means it took the point as local,
    #   moved means it converted it out of the session's space.
    # ------------------------------------------------------------
    def self.Na__DeepPick__AddTransform(model, entities, sample_local)
        identity = Geom::Transformation.new
        return identity unless entities && sample_local
        return identity unless model.respond_to?(:edit_transform)

        edit = model.edit_transform
        return identity if edit.nil?

        sample_session = sample_local.transform(edit)
        return identity if sample_session.distance(sample_local) < NA_DEEP_PICK_SPACE_TOL

        # The size guard matters: if SketchUp merged the probe into a
        # construction point the user already had there, erasing it would take
        # THEIR point with it. A merge answers the question just as well, so it
        # is read and left alone.
        before = entities.size
        probe  = entities.add_cpoint(sample_session)
        landed = probe.position.clone                                         # <-- Copied out: it is read again AFTER the erase below
        probe.erase! if probe.valid? && entities.size > before

        landed.distance(sample_session) < NA_DEEP_PICK_SPACE_TOL ? identity : edit
    rescue StandardError
        Geom::Transformation.new
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Path Inspection
    # -----------------------------------------------------------------------------

    # FUNCTION | Instances Along a Pick Path, Outermost First
    # ------------------------------------------------------------
    def self.Na__DeepPick__Instances(path)
        return [] unless path.is_a?(Array)

        path.select do |entity|
            entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Groups or Components Deep the Face Sits
    # ------------------------------------------------------------
    def self.Na__DeepPick__NestingDepth(path)
        Na__InsertPrimatives.Na__DeepPick__Instances(path).length
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is Anything on the Path Locked?
    # ------------------------------------------------------------
    def self.Na__DeepPick__PathLocked?(path)
        Na__InsertPrimatives.Na__DeepPick__Instances(path).any? do |instance|
            instance.respond_to?(:locked?) && instance.locked?
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Instances Share the Definition Being Edited
    # More than one means a push here changes every copy in the model.
    # ------------------------------------------------------------
    def self.Na__DeepPick__SharedInstanceCount(path)
        innermost = Na__InsertPrimatives.Na__DeepPick__Instances(path).last
        return 1 unless innermost && innermost.respond_to?(:definition)

        definition = innermost.definition
        return 1 unless definition

        count = definition.instances.length
        count < 1 ? 1 : count
    rescue StandardError
        1
    end
    # ---------------------------------------------------------------

    # FUNCTION | Force Every Definition on the Path to Re-Measure Itself
    # A definition caches its bounding box, and editing its entities from OUTSIDE
    # the editing context does not always dirty that cache. The push then really
    # has happened — the model holds the new geometry and will happily pick it —
    # but the viewport keeps drawing the old shape until something else forces a
    # rebuild. That is the "nothing happened, then a second later it did, and
    # meanwhile I could select invisible faces" behaviour.
    #
    # Innermost first, because an outer definition's bounds depend on the inner
    # ones having been recomputed already.
    # ------------------------------------------------------------
    def self.Na__DeepPick__InvalidateDefinitions(path)
        instances = Na__InsertPrimatives.Na__DeepPick__Instances(path).reverse

        instances.each do |instance|
            next unless instance.respond_to?(:definition)

            definition = instance.definition
            next unless definition && definition.respond_to?(:invalidate_bounds)

            definition.invalidate_bounds
        end

        instances.length
    rescue StandardError
        0
    end
    # ---------------------------------------------------------------

    # FUNCTION | Readable Description of Where the Face Lives
    # ------------------------------------------------------------
    def self.Na__DeepPick__PathLabel(target)
        return 'model' unless target

        depth = target[:depth].to_i
        return 'Loose geometry' if depth.zero?                                # <-- Not in any group or component

        instances = Na__InsertPrimatives.Na__DeepPick__Instances(target[:path])
        innermost = instances.last
        name      = ''

        begin
            name = innermost.name.to_s
            name = innermost.definition.name.to_s if name.empty? && innermost.respond_to?(:definition)
        rescue StandardError
            name = ''
        end

        label = name.empty? ? 'unnamed' : name
        "#{label} (#{depth} deep)"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Geometry Extraction
    # -----------------------------------------------------------------------------

    # FUNCTION | Triangles of a Face in World Space
    # Taken from the face's own PolygonMesh rather than its outer loop, so holes
    # and concave outlines shade correctly instead of being filled over.
    # ------------------------------------------------------------
    def self.Na__DeepPick__WorldTriangles(face, xform)
        return [] unless face && face.valid?

        mesh      = face.mesh
        triangles = []

        mesh.polygons.each do |polygon|
            next unless polygon.length == 3

            points = polygon.map { |index| mesh.point_at(index.abs).transform(xform) }
            triangles << points
        end

        triangles
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Outer Loop of a Face in World Space
    # ------------------------------------------------------------
    def self.Na__DeepPick__WorldOuterLoop(face, xform)
        return [] unless face && face.valid?

        face.outer_loop.vertices.map { |vertex| vertex.position.transform(xform) }
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Area of a Face in World Square Metres
    # ------------------------------------------------------------
    def self.Na__DeepPick__WorldAreaM2(face, xform)
        return '0.00' unless face && face.valid?

        area_mm2 = face.area(xform) * NA_DRAWN_INCH_TO_MM * NA_DRAWN_INCH_TO_MM
        format('%.2f', area_mm2 / 1_000_000.0)
    rescue StandardError
        '0.00'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP NESTED FACE PICKING MODULE
# =============================================================================
