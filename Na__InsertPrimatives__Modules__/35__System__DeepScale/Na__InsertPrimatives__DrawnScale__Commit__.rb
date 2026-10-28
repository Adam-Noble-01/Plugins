# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE COMMIT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScale__Commit__.rb
# NAMESPACE  : Na__InsertPrimatives
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
#
# ONE OBJECT CHANGES, NOT EVERY COPY:
# - A stretch edits a definition, and a definition can be shared. Scaling one
#   window must not resize every window of its type, so a shared object is
#   made unique first, and so is any shared part inside it that a plane runs
#   through. Its stretch planes are copied across, so the unique copy still
#   knows where it stretches. Parts carried whole stay shared.
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
# NEVER CLOSED ALL THE WAY:
# - Na__ScaleCommit__CheckRoom measures the real geometry before anything is
#   touched and refuses a shrink that would bring details either side of a
#   plane within NA_SCALE_MIN_GAP of each other. The tool's drag limit reads
#   the same rule from its ghost; this is the last word, for an object too
#   big for the ghost to have seen every point of.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

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
        return { :success => false, :error => 'nothing to change' } if Na__InsertPrimatives.Na__ScaleField__Identity?(field)
        return { :success => false, :error => 'the sizes worked out to nonsense — nothing was changed' } unless Na__InsertPrimatives.Na__ScaleField__Finite?(field)
        return Na__InsertPrimatives.Na__ScaleCommit__ScaleLoose(model, frame, field) if frame[:loose]

        if field[:stretch]
            Na__InsertPrimatives.Na__ScaleCommit__Stretch(model, frame, field, planes_after)
        else
            Na__InsertPrimatives.Na__ScaleCommit__Scale(model, frame, field)
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
        parent_path = Na__InsertPrimatives.Na__DeepPick__Instances(frame[:path])[0...-1]
        local       = Na__InsertPrimatives.Na__ScaleField__Affine(field, frame[:min])
        world_delta = frame[:world] * local * frame[:inverse]
        parent      = parent_path.empty? ? nil : Na__InsertPrimatives.Na__ScaleFrame__WorldTransform(parent_path)

        result = Na__InsertPrimatives.Na__DeepPick__ExecuteInContext(model, parent_path, NA_SCALE_OP_SCALE) do |_entered|
            wanted   = parent_path.empty? ? nil : parent_path
            in_world = Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, wanted) || parent.nil?
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

        unless Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, frame[:context])
            return result.merge(:error => 'the open group changed since the geometry was taken — select it again')
        end

        list = frame[:entities].select(&:valid?)
        return result.merge(:error => 'the geometry is no longer there') if list.empty?

        delta = frame[:world] * Na__InsertPrimatives.Na__ScaleField__Affine(field, frame[:min]) * frame[:inverse]
        model.start_operation(NA_SCALE_OP_SCALE, true)

        begin
            model.active_entities.transform_entities(delta, list)
            model.commit_operation
            result.merge(:success => true, :moved => list.length)
        rescue StandardError => error
            model.abort_operation
            result.merge(:error => error.message)
        end
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
    # A context that will not open stops the walk there, and the user's own
    # context is put back either way. Nothing is ever edited from outside.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Stretch(model, frame, field, planes_after)
        instance = frame[:instance]
        path     = Na__InsertPrimatives.Na__DeepPick__Instances(frame[:path])
        tally    = { :unique => 0, :rigid => 0, :opened => 0, :moved => 0, :base => path.length }
        failed   = Na__InsertPrimatives.Na__ScaleCommit__CheckRoom(frame, field)
        return Na__InsertPrimatives.Na__ScaleCommit__Result(false, failed, tally) if failed

        previous = model.active_path
        selected = Na__InsertPrimatives.Na__DeepPick__FocusSnapshot(model)  # <-- Entering a context clears this
        pending  = false                                                    # <-- An edit committed next_transparent, its next entry still to come

        if instance.definition.instances.length > 1
            model.start_operation(NA_SCALE_OP_STRETCH, true, true, false)     # <-- next_transparent: the object's context entry joins this step

            begin
                Na__InsertPrimatives.Na__ScaleCommit__MakeUnique(instance)
                model.commit_operation
                tally[:unique] += 1
                pending = true
            rescue StandardError => error
                model.abort_operation
                return Na__InsertPrimatives.Na__ScaleCommit__Result(false, "could not make #{frame[:name]} unique — #{error.message}", tally)
            end
        end

        queue  = [path]
        failed = nil

        until queue.empty?
            target = queue.shift

            unless Na__InsertPrimatives.Na__ScaleCommit__Enter(model, target)
                failed = "#{Na__InsertPrimatives.Na__DeepPick__InstanceName(target.last)} would not open for editing — the stretch stopped there; Ctrl+Z takes back what was done"
                break
            end

            pending = false
            model.start_operation(NA_SCALE_OP_STRETCH, true, true, true)      # <-- Joins the entry just made, pulls in the next

            begin
                queue.concat(Na__InsertPrimatives.Na__ScaleCommit__StretchContext(model, frame, field, target, tally))
                Na__InsertPrimatives.Na__ScalePlanes__Write(instance.definition, planes_after) if planes_after && target.length == path.length
                model.commit_operation
                pending = true
            rescue StandardError => error
                model.abort_operation
                failed = error.message
                break
            end
        end

        restored = Na__InsertPrimatives.Na__ScaleCommit__Restore(model, previous)
        Na__InsertPrimatives.Na__ScaleCommit__ClosePending(model) if pending && !restored
        Na__InsertPrimatives.Na__DeepPick__FocusRestore(model, selected)

        Na__InsertPrimatives.Na__ScaleCommit__Result(failed.nil?, failed, tally)
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Stretch's Answer in the Shape the Tool Reads
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Result(success, error, tally)
        {
            :success => success,
            :error   => error,
            :mode    => :stretch,
            :unique  => tally[:unique],
            :rigid   => tally[:rigid],
            :opened  => tally[:opened],
            :moved   => tally[:moved]
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open One Context; True Only Once It Really Is the Open One
    # ------------------------------------------------------------
    # active_path= refuses to run inside an open operation, so this is only
    # ever called between them.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Enter(model, target)
        return true if Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, target)

        model.active_path = target
        Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, target)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put the User Back Where They Were; True If the Context Changed
    # Falls back to the root rather than ever leaving them inside a part the
    # stretch opened.
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__Restore(model, previous)
        return false if Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, previous)

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
    # ------------------------------------------------------------
    def self.Na__ScaleCommit__StretchContext(model, frame, field, target, tally)
        unless Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, target)
            raise ArgumentError, "#{Na__InsertPrimatives.Na__DeepPick__InstanceName(target.last)} is not the open context"
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

        moved   = []
        vectors = []

        vertices.each_value do |vertex|
            reported = vertex.position
            goal     = Na__InsertPrimatives.Na__ScaleField__MapPoint(field, reported.transform(inverse)).transform(world)
            vector   = goal - reported
            raise ArgumentError, 'a point would go to an impossible place' unless [vector.x, vector.y, vector.z].all? { |value| value.to_f.finite? }
            next if vector.length.to_f < NA_SCALE_MOVE_TOL

            moved   << vertex
            vectors << vector
        end

        entities.transform_by_vectors(moved, vectors) unless moved.empty?
        tally[:moved] += moved.length

        if target.length > tally[:base]
            Na__InsertPrimatives.Na__ScaleCommit__CarryPartPlanes(target.last, inverse * model.edit_transform, field)
            tally[:opened] += 1
        end

        next_in_line = []

        parts.each do |part|
            next unless part.valid?

            part_local = inverse * part.transformation
            mins, maxs = Na__InsertPrimatives.Na__ScaleCommit__LocalBox(part.definition.bounds, part_local)
            rigid      = Na__InsertPrimatives.Na__ScaleField__RigidOver?(field, mins, maxs)
            rigid    ||= (target.length + 1 - tally[:base]) > NA_SCALE_MAX_DEPTH   # <-- Past the depth guard a part is carried, never half-stretched

            if rigid
                part.transform!(world * Na__InsertPrimatives.Na__ScaleField__Affine(field, mins) * inverse)
                tally[:rigid] += 1
                next
            end

            # Closed here, so it can still be made unique before its turn.
            if part.definition.instances.length > 1
                Na__InsertPrimatives.Na__ScaleCommit__MakeUnique(part)
                tally[:unique] += 1
            end

            next_in_line << (target + [part])
        end

        next_in_line
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
        shrinking = NA_SCALE_AXES.select { |axis| field[axis][:mode] == :stretch && field[axis][:delta].to_f < 0.0 }
        return nil if shrinking.empty?

        coords = { :x => [], :y => [], :z => [] }
        Na__InsertPrimatives.Na__ScaleCommit__CollectCoords(frame[:instance].definition, Geom::Transformation.new, field, coords, 0)

        shrinking.each do |axis|
            n     = NA_SCALE_AXIS_INDEX[axis]
            spec  = field[axis]
            keep  = NA_SCALE_MIN_GAP.to_f / frame[:scales][n]
            least = Na__InsertPrimatives.Na__ScaleField__StretchMinDelta(spec[:planes], spec[:centre], frame[:local_lengths][n], coords[axis], keep)
            next if spec[:delta].to_f >= least - 1e-9

            floor = Na__InsertPrimatives.Na__DrawnFormat__Mm((frame[:local_lengths][n] + least) * frame[:scales][n])
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
                mins, maxs = Na__InsertPrimatives.Na__ScaleCommit__LocalBox(entity.definition.bounds, part_local)

                if Na__InsertPrimatives.Na__ScaleField__RigidOver?(field, mins, maxs) || depth + 1 > NA_SCALE_MAX_DEPTH
                    NA_SCALE_AXES.each_with_index { |axis, n| coords[axis].push(mins[n], maxs[n]) }
                else
                    Na__InsertPrimatives.Na__ScaleCommit__CollectCoords(entity.definition, part_local, field, coords, depth + 1)
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
        planes = Na__InsertPrimatives.Na__ScalePlanes__Read(before)

        instance.make_unique

        after = instance.definition
        Na__InsertPrimatives.Na__ScalePlanes__Write(after, planes) if !after.equal?(before) && Na__InsertPrimatives.Na__ScalePlanes__Total(planes) > 0
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
        planes     = Na__InsertPrimatives.Na__ScalePlanes__Read(definition)
        return false if Na__InsertPrimatives.Na__ScalePlanes__Total(planes).zero?

        units = [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1)]
        moved = Na__InsertPrimatives.Na__ScalePlanes__Empty

        NA_SCALE_AXES.each_with_index do |axis, n|
            list = planes[axis]
            next if list.empty?

            along  = Na__InsertPrimatives.Na__ScaleFrame__WorldVector(part_local, units[n])
            length = along.length.to_f
            target = (0..2).find { |index| length > 0.0 && (along[index].abs / length) > 0.9999 }

            unless target
                moved[axis] = list.dup
                next
            end

            moved[axis] = list.map do |value|
                spot       = Geom::Point3d.new(n.zero? ? value : 0.0, n == 1 ? value : 0.0, n == 2 ? value : 0.0).transform(part_local)
                carried    = Na__InsertPrimatives.Na__ScaleField__Value(field[NA_SCALE_AXES[target]], spot[target])
                value + ((carried - spot[target]) / along[target])
            end
        end

        Na__InsertPrimatives.Na__ScalePlanes__Write(definition, moved)
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: a part's planes were not carried — #{error.message}"
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
            Na__InsertPrimatives.Na__ScalePlanes__Write(definition, planes)
            model.commit_operation
            true
        rescue StandardError => error
            model.abort_operation
            Na__InsertPrimatives.Na__Debug__Puts "NA DEEP SCALE: #{op_name} failed — #{error.message}"
            false
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE COMMIT
# =============================================================================
