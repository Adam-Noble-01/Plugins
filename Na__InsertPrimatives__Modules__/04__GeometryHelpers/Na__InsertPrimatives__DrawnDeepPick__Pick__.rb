# =============================================================================
# NA INSERT PRIMATIVES - DEEP PICK FACE AND EDGE SCAN
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnDeepPick__Pick__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Face and edge picks at any nesting depth, with open-context bias
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

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
    #
    # THE PICK IS RELATIVE TO THE OPEN CONTEXT (see the hub header):
    # - path_at starts "from the active entities" and transformation_at maps the
    #   leaf "into the coordinates of the active entities" — which are GLOBAL
    #   while a context is open. So the transform is already the one the tools
    #   want, and the path is made absolute here so it can be handed to
    #   Model#active_path=, which only accepts a path from the model root.
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
        # The path is the OPEN CONTEXT's, so the commit knows it is already in
        # the right place and the depth reads true. The transform is the
        # IDENTITY: a face in the open context already reports its positions
        # and normal in global coordinates (the rule in the hub header), so
        # there is nothing left to apply. Applying edit_transform here — as the
        # tools did up to 5.1.1 — moved every preview by the open group's own
        # transform, which was then hidden by an equal and opposite correction
        # at draw time, and which broke the moment anything ELSE was drawn.
        if direct.is_a?(Sketchup::Face) && Na__InsertPrimatives.Na__DeepPick__InOpenContext?(direct)
            target = Na__InsertPrimatives.Na__DeepPick__BuildTarget(
                direct,
                Na__InsertPrimatives.Na__DeepPick__ContextPath,
                nil
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
                    leaf,
                    Na__InsertPrimatives.Na__DeepPick__AbsolutePath(helper.path_at(index)),
                    helper.transformation_at(index)
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

    # FUNCTION | A Pick Path Made Absolute — Model Root to Innermost Instance
    # ------------------------------------------------------------
    # PickHelper#path_at starts at the ACTIVE entities, so inside an opened
    # group the instances the user is standing in are simply not in it. Hand
    # such a path to Model#active_path= and SketchUp refuses it (an instance
    # path must chain from the root), the commit falls back to editing the
    # definition from outside, and the display cache goes stale — the whole
    # saga the push tool was cured of at the root, back again one level down.
    #
    # Prepending the open context's own instances gives a path SketchUp will
    # open, a depth that reads true in the status bar, and a locked test that
    # sees every ancestor. Only instances are kept; the leaf is dropped, which
    # is what every path helper here expects.
    # ------------------------------------------------------------
    def self.Na__DeepPick__AbsolutePath(relative_path)
        context = Na__InsertPrimatives.Na__DeepPick__ContextPath || []

        context + Na__InsertPrimatives.Na__DeepPick__Instances(relative_path)
    rescue StandardError
        Na__InsertPrimatives.Na__DeepPick__Instances(relative_path)
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
    # `path` is ABSOLUTE — model root to the innermost instance the face sits
    # in — so it can be opened, counted and checked for locks. `transformation`
    # carries the face's REPORTED coordinates to global: transformation_at for
    # a face inside a closed group, nil (the identity) for a face in the open
    # context, whose coordinates are global already.
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
        # Identity transform, as for faces: an open-context edge reports global.
        if direct.is_a?(Sketchup::Edge) && Na__InsertPrimatives.Na__DeepPick__InOpenContext?(direct)
            target = Na__InsertPrimatives.Na__DeepPick__BuildEdgeTarget(
                direct,
                Na__InsertPrimatives.Na__DeepPick__ContextPath,
                nil
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
                    leaf,
                    Na__InsertPrimatives.Na__DeepPick__AbsolutePath(helper.path_at(index)),
                    helper.transformation_at(index)
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
    # `path` and `transformation` follow the same rule as Na__DeepPick__BuildTarget.
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

end

# =============================================================================
# END OF FILE
# =============================================================================
