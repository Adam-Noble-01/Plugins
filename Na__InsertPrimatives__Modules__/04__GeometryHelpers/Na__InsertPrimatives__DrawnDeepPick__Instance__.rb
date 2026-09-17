# =============================================================================
# NA INSERT PRIMATIVES - DEEP PICK INSTANCE SCAN
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnDeepPick__Instance__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Pick the group or component under the cursor, with its world box
# CREATED    : 2026
#
# DESCRIPTION:
# - The face and edge scans in the sibling files hunt the DEEPEST thing under
#   the cursor, because a push or a chamfer acts on one surface. Subtraction is
#   the opposite question: "which object am I cutting?" — and the answer a user
#   means is the one a single click of the Select tool would grab, the
#   OUTERMOST instance inside the context they have open. Whatever is nested
#   below it comes along as its contents, which is exactly what the subtract
#   pipeline then walks.
# - So this scan takes instances.first from each pick path rather than the leaf,
#   and prefers a selected instance when there is one, on the same reasoning as
#   the face scan: a selection is an instruction, not decoration.
#
# THE TRANSFORMATION, AND WHY IT IS READ STRAIGHT OFF THE INSTANCE:
# - PickHelper#path_at starts at the ACTIVE entities, so instances.first lives
#   directly in the context the user has open. Its #transformation is expressed
#   in its parent's coordinate system — the active context — and the coordinate
#   rule (see the DeepPick hub header) is that the active context and all its
#   parents report GLOBAL coordinates. So the instance's own transformation is
#   already the world one, with nothing to accumulate.
# - Below it the rule flips: a child of a CLOSED group reports local
#   coordinates, so a descendant's world transform is parent_world * its own.
#   That accumulation lives in the subtract scan, which is the only thing that
#   needs to walk down there.
#
# TARGET HASH:
#   :instance       the group or component itself
#   :path           ABSOLUTE, model root to and INCLUDING :instance
#   :context        :path without the last entry — the collection it lives in
#   :transformation :instance's own transform, mapping its definition to world
#   :depth          how many instances deep :instance sits
#   :locked         the instance or an ancestor is locked
#   :shared_count   how many instances share its definition
#   :name           what to call it in the status bar
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Instance Picking
    # -----------------------------------------------------------------------------

    # FUNCTION | Find the Group or Component Under the Cursor
    # Returns nil over empty space, and nil over loose geometry in the open
    # context — loose geometry is not in any container, so there is nothing to
    # name as the thing being cut.
    # ------------------------------------------------------------
    def self.Na__DeepPick__InstanceAt(view, x, y)
        helper = view.pick_helper
        helper.do_pick(x, y)

        count = helper.count.to_i
        limit = count < NA_DEEP_PICK_MAX_PATHS ? count : NA_DEEP_PICK_MAX_PATHS
        focus = Na__InsertPrimatives.Na__DeepPick__FocusSet

        # PASS 0 — the instance the user has SELECTED, when one of the picks
        # runs through it. The selected instance itself is the target, not the
        # outermost thing around it: having selected the inner group, being
        # handed its parent would be the tool arguing with the user.
        if focus
            selected = Na__InsertPrimatives.Na__DeepPick__FocusedInstanceAt(helper, focus, limit)
            return selected if selected
        end

        index = 0

        while index < limit
            instances = Na__InsertPrimatives.Na__DeepPick__Instances(helper.path_at(index))

            unless instances.empty?
                target = Na__InsertPrimatives.Na__DeepPick__BuildInstanceTarget(instances.first)

                # Locked is invisible here for the same reason it is everywhere
                # else in this plugin: the scan carries on to whatever stands
                # behind it rather than offering something that cannot be cut.
                return target if target && !target[:locked]
            end

            index += 1
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Selected Instance Under the Cursor, or nil
    # ------------------------------------------------------------
    # Only instances.first is tested, and that is not a shortcut. A SketchUp
    # selection can only hold entities from the context the user has open, so a
    # selected instance is by definition the outermost one on the path — and
    # only the outermost one can have its #transformation read as world. Testing
    # deeper entries would find nothing that is not already here, and would
    # quietly hand back a target whose transform is in the wrong space.
    # ------------------------------------------------------------
    def self.Na__DeepPick__FocusedInstanceAt(helper, focus, limit)
        index = 0

        while index < limit
            candidate = Na__InsertPrimatives.Na__DeepPick__Instances(helper.path_at(index)).first

            if candidate && focus[candidate.entityID]
                target = Na__InsertPrimatives.Na__DeepPick__BuildInstanceTarget(candidate)
                return target if target && !target[:locked]
            end

            index += 1
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Assemble Everything the Subtract Tool Needs About an Instance
    # ------------------------------------------------------------
    def self.Na__DeepPick__BuildInstanceTarget(instance)
        return nil unless instance && instance.valid?

        path = Na__InsertPrimatives.Na__DeepPick__AbsolutePath([instance])

        {
            :instance       => instance,
            :path           => path,
            :context        => path[0...-1] || [],
            :transformation => instance.transformation,
            :depth          => path.length,
            :locked         => Na__InsertPrimatives.Na__DeepPick__PathLocked?(path),
            :shared_count   => Na__InsertPrimatives.Na__DeepPick__SharedInstanceCount(path),
            :name           => Na__InsertPrimatives.Na__DeepPick__InstanceName(instance)
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | What to Call an Instance in the Status Bar
    # ------------------------------------------------------------
    def self.Na__DeepPick__InstanceName(instance)
        return 'unnamed' unless instance && instance.valid?

        name = instance.name.to_s
        name = instance.definition.name.to_s if name.empty? && instance.respond_to?(:definition)
        name.empty? ? 'unnamed' : name
    rescue StandardError
        'unnamed'
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Instance Geometry in World Space
    # -----------------------------------------------------------------------------

    # FUNCTION | The Eight Corners of an Instance's Own Box, in World Space
    # ------------------------------------------------------------
    # definition.bounds is the box in the instance's OWN axes, so transforming
    # its corners gives a box that stays wrapped around a rotated object.
    # instance.bounds would be the world-axis-aligned box instead, which on the
    # angled wall in the reference screenshot is several times too big and
    # points the wrong way — useless as a "this is what you are about to cut"
    # highlight.
    #
    # Returned as [near_quad, far_quad], each four points in loop order, which
    # is the shape Na__DrawnPreview__DrawFilledBox takes.
    # ------------------------------------------------------------
    def self.Na__DeepPick__InstanceBoxQuads(instance, xform)
        bounds = Na__InsertPrimatives.Na__DeepPick__InstanceLocalBounds(instance)
        return nil unless bounds
        return nil if bounds.empty?

        matrix  = xform || Geom::Transformation.new
        corners = (0..7).map { |index| bounds.corner(index).transform(matrix) }

        [
            [corners[0], corners[1], corners[3], corners[2]],                 # <-- Bottom face, wound as a loop
            [corners[4], corners[5], corners[7], corners[6]]                  # <-- Top face, same winding so the sides close
        ]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Instance's Bounding Box in Its Own Definition Space
    # ------------------------------------------------------------
    def self.Na__DeepPick__InstanceLocalBounds(instance)
        return nil unless instance && instance.valid?
        return instance.definition.bounds if instance.respond_to?(:definition) && instance.definition

        instance.bounds
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Instance's Bounding Box as a World-Axis Box
    # Built from the eight transformed corners rather than from instance.bounds,
    # so it is honest about a nested instance whose own #bounds is reported in
    # its parent's space rather than the world's.
    # ------------------------------------------------------------
    def self.Na__DeepPick__InstanceWorldBounds(instance, xform)
        quads = Na__InsertPrimatives.Na__DeepPick__InstanceBoxQuads(instance, xform)
        return nil unless quads

        box = Geom::BoundingBox.new
        quads.each { |quad| quad.each { |point| box.add(point) } }
        box
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Centre of an Instance in World Space
    # ------------------------------------------------------------
    def self.Na__DeepPick__InstanceWorldCentre(instance, xform)
        box = Na__InsertPrimatives.Na__DeepPick__InstanceWorldBounds(instance, xform)
        return nil unless box && !box.empty?

        box.center
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Do Two World Boxes Share Any Volume?
    # The cheap gate in front of every solid operation: a boolean against a
    # solid the cutter cannot possibly reach is pure cost, and a failed one is
    # a nil return the caller then has to reason about.
    # ------------------------------------------------------------
    def self.Na__DeepPick__BoxesOverlap?(box_a, box_b)
        return false unless box_a && box_b
        return false if box_a.empty? || box_b.empty?

        overlap = box_a.intersect(box_b)
        !overlap.nil? && !overlap.empty?
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PICK INSTANCE SCAN
# =============================================================================
