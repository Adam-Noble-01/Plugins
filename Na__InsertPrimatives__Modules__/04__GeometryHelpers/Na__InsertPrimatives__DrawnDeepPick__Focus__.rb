# =============================================================================
# NA INSERT PRIMATIVES - DEEP PICK SELECTION FOCUS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnDeepPick__Focus__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Treat the current selection as a pick bias for nested groups
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

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

end

# =============================================================================
# END OF FILE
# =============================================================================
