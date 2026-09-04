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

end

# =============================================================================
# END OF FILE
# =============================================================================
