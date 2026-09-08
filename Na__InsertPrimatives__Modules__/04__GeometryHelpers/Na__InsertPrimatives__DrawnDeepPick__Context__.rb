# =============================================================================
# NA INSERT PRIMATIVES - DEEP PICK CONTEXT OPERATIONS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnDeepPick__Context__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Enter a nested editing context, run a model edit, then restore it
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Context-Managed Operations
    # -----------------------------------------------------------------------------

    # FUNCTION | Are Two Editing Contexts the Same Place?
    # nil is the model root. Compared as arrays because an InstancePath and the
    # Array a tool built from a pick are the same path in two different clothes.
    # Shared by the push commit, the chamfer commit and every revise, so the
    # three can never disagree about what "still in the same group" means.
    # ------------------------------------------------------------
    def self.Na__DeepPick__SameContext?(current, wanted)
        return true if current.nil? && wanted.nil?
        return false if current.nil? || wanted.nil?

        current.to_a == wanted.to_a
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

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
    # THE BLOCK IS TOLD WHETHER THE CONTEXT WAS ENTERED, AND MUST CARE:
    # - Entering a group flips the coordinate space its geometry is reported
    #   and accepted in, from definition-local to global (the rule in the hub
    #   header). Points read from the target BEFORE this call are therefore in
    #   local space when the group was closed, and once it is open the
    #   collection takes global — so they must go through model.edit_transform
    #   (read INSIDE the block, where it is the newly opened session's) on the
    #   way in. Points read inside the block are already global and want no
    #   transform at all. Nothing entered — the target is in the user's own
    #   context, or the open failed — and reads and adds share one space.
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

                unless Na__InsertPrimatives.Na__DeepPick__SameContext?(previous, target_path)
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
            yield(entered)
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
    # Returns the transformation to apply to points READ FROM this collection
    # a moment ago before handing them back to entities.add_*. Under the rule
    # in the hub header that is always the identity — a collection reports and
    # accepts the same space, global while it is open, local while it is
    # closed — and this probe agrees, because a point that comes back exactly
    # as it went in is what "same space" looks like.
    #
    # KEPT AS A MEASUREMENT, NOT A GUESS:
    # - The push tool's quad ring and loop cut hand this points captured INSIDE
    #   the operation, from the very collection they are added back to. A
    #   construction point is inert, is added and erased inside the caller's
    #   own operation, and reading its position back is proof of the space
    #   rather than a belief about it. It cost three chamfer releases to learn
    #   that belief is not enough here.
    # - It is NOT the right tool for points read before a context was entered:
    #   those are local, the open collection takes global, and the probe would
    #   still answer identity because the probe point itself round-trips. The
    #   chamfer commit uses Model#edit_transform for that case instead.
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

end

# =============================================================================
# END OF FILE
# =============================================================================
