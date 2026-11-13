# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP EDITS IN SHARED COMPONENTS
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnDeepUnique__.rb
# NAMESPACE  : Na__NobleDrawingTools
# AUTHOR     : Noble Architecture
# PURPOSE    : Let a deep edit change exactly the copies it was aimed at:
#              copies that change alike share one definition and are edited
#              once, copies the edit does not reach keep the one they had
# CREATED    : 2026
#
# DESCRIPTION:
# - A deep tool reaches geometry through instance PATHS, and one definition
#   can sit at the end of many of them: thirty balusters are thirty paths
#   into one definition. Before 5.2.43 Deep Vertex Move opened and moved that
#   definition once per path, so the same vertices moved thirty times, each
#   move its own undo step, and every copy in the model moved with them,
#   picked or not. Deep Scale made each baluster its own definition before
#   stretching it: thirty definitions where there had been one.
# - Now a deep edit is PLANNED before anything changes. Each path it runs
#   through is a NODE, and each node has a SIGNATURE: what the edit does to
#   its definition, read in that definition's own axes, down through
#   everything below it. Copies with one signature want exactly the same
#   change, so they can share a definition; copies with two cannot.
# - Each definition is then decided once, against every place it shows in
#   the whole model (OCCURRENCES: a copy inside a group placed three times
#   shows three times, and so does everything inside the group the user has
#   open when that group has copies):
#     KEEP     every occurrence is a node, all with one signature: the
#              definition itself is edited, once, and stays shared. Thirty
#              balusters picked alike and no others: one edit, one
#              definition.
#     ISOLATE  otherwise the nodes of each signature are given one new
#              definition of their own: make_unique on the first copy,
#              definition= on the rest (the pairing ruby.sketchup.com
#              offers for "these copies, apart from the others"), so the
#              copies the edit does not reach keep the old one. When no
#              occurrence lies outside the edit, the signature with the
#              most nodes keeps the old definition and only the others move.
# - The tool then opens and edits ONE copy of each final definition (its
#   REPRESENTATIVE). Every other copy of it (a RIDER) follows, as copies of a
#   component do. One edit however many copies, inside one undo step.
#
# GROUPS:
# - Group copies share a definition until one is edited, but a group has no
#   definition= (only make_unique), and editing or opening one copy can make
#   it unique by itself (Group#entities on ruby.sketchup.com; NDT 5.2.4). So
#   every group is a signature of its own: one that has to part from its
#   copies is made unique and edited on its own, as SketchUp does when a copy
#   is opened. A group whose copies are all in the edit keeps its definition.
#
# NEVER EDITED:
# - Live Components (live_component?, 2021.0: the API says they should not be
#   modified) and procedural definitions (procedural?, 2027.0: their entities
#   are the procedure's output). Refused before anything changes, by name,
#   and so is a locked object the edit would have to open.
#
# MAKE UNIQUE IS CHECKED, NOT TRUSTED:
# - api-issue-tracker #952 (SKEXT-4120, open): after C1.make_unique the new
#   definition can land on another copy, C2. So the definition is read back.
#   For components a misplaced one is swapped back with definition=; a group,
#   or anything that still will not part, is refused by name.
#
# ORDER, AND WHERE THE SPLIT HAPPENS:
# - A container is settled before anything inside it, and make_unique runs
#   while the instance is closed. So the copies standing in the user's own
#   context are settled there, and every other copy is settled in the open
#   context of the representative it stands in, just before that context's
#   own edit — the house rule (note 12) that nothing is changed from outside
#   its context.
# - Settling a container copies everything in it, so a part planned against
#   the old definition is found again in the new one by its definition and
#   where it stands (Na__DeepUnique__Rebind): an exact copy stands exactly
#   there. World where its container is open, local where it is closed.
#
# UNDO:
# - Nothing here opens an operation: the tools call SettleIn inside their own,
#   so the split and the edit it made way for are one Ctrl+Z.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__NobleDrawingTools__DrawnDeepPick__'
require_relative 'Na__NobleDrawingTools__DrawnDeepPick__Focus__'
require_relative 'Na__NobleDrawingTools__DrawnDeepPick__Context__'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Deep Unique Constants
    # -----------------------------------------------------------------------------

    NA_DEEP_UNIQUE_QUANTUM   = 1e-5                                           # <-- Inches; two local moves closer than this are the same move
    NA_DEEP_UNIQUE_PLACE_TOL = 1e-6                                           # <-- Relative; a copied part stands exactly where its original did
    NA_DEEP_UNIQUE_MAX_WORK  = 300_000                                        # <-- Points signed across all copies; past it each copy signs as itself

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Names and Kinds
    # -----------------------------------------------------------------------------

    # FUNCTION | Is This a Group or a Component Instance?
    # ------------------------------------------------------------
    # In Ruby a Group is NOT a ComponentInstance (sibling classes), so both
    # are named.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Instance?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This a Component — Something definition= Can Move?
    # ------------------------------------------------------------
    # Asked as "a ComponentInstance and not a Group", so it holds wherever a
    # Group is modelled as a kind of ComponentInstance (the C API's view).
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Component?(entity)
        entity.is_a?(Sketchup::ComponentInstance) && !entity.is_a?(Sketchup::Group)
    end
    # ---------------------------------------------------------------

    # FUNCTION | What to Call an Instance or a Definition in a Message
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Name(entity)
        return 'an object' unless entity && entity.valid?

        name = entity.respond_to?(:name) ? entity.name.to_s : ''
        name = entity.definition.name.to_s if name.empty? && entity.respond_to?(:definition) && entity.definition
        name.empty? ? (entity.is_a?(Sketchup::Group) ? 'a group' : 'a component') : name
    rescue StandardError
        'an object'
    end
    # ---------------------------------------------------------------

    # FUNCTION | Why a Deep Edit May Not Change This Definition, or nil
    # ------------------------------------------------------------
    # Both checks are feature-detected: live_component? is 2021.0 and
    # procedural? is 2027.0, so SketchUp 2026 simply has no procedures.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Refusal(definition)
        return nil unless definition && definition.valid?

        name = Na__NobleDrawingTools.Na__DeepUnique__Name(definition)

        if definition.respond_to?(:live_component?) && definition.live_component?
            return "#{name} is a Live Component — SketchUp builds its geometry, so a deep edit cannot change it"
        end

        if definition.respond_to?(:procedural?) && definition.procedural?
            return "#{name} is a procedural component — its procedure makes its geometry, so a deep edit cannot change it"
        end

        nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Plan
    # -----------------------------------------------------------------------------

    # FUNCTION | A New, Empty Plan for One Deep Edit
    # ------------------------------------------------------------
    def self.Na__DeepUnique__NewPlan(model)
        {
            :model     => model,
            :roots     => [],                                                 # <-- Nodes standing in the user's own context
            :by_def    => {},                                                 # <-- Definition => every node using it, at every depth
            :decisions => {},                                                 # <-- Definition => { :keep, :outside, :nodes, :classes }
            :registry  => {},                                                 # <-- [definition, class] => the definition made for that class
            :finals    => {},                                                 # <-- Final definition => its representative node
            :riders    => Hash.new(0),                                        # <-- Final definition => copies riding on its one edit
            :memo      => {},                                                 # <-- Occurrence counts, per definition
            :mult      => 1,                                                  # <-- Occurrences of the user's own context
            :work      => 0,                                                  # <-- Points signed so far (Na__DeepUnique__Spend)
            :refused   => nil,
            :made      => 0,                                                  # <-- New definitions made by make_unique
            :joined    => 0,                                                  # <-- Copies moved onto one of them with definition=
            :repaired  => 0                                                   # <-- make_unique answers put right (#952)
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Add One Node: One Path the Edit Runs Through
    # ------------------------------------------------------------
    # `world` is the instance's definition axes to world, as planned. The
    # instance's own transformation is read now, with only the user's context
    # open: world for a copy standing in it, local to its parent below it.
    # A node with role :place (payload) is a copy whose PLACEMENT the edit
    # changes but whose definition it does not, so it is found again (Rebind)
    # but never settled.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__AddNode(plan, instance, parent, world, payload = {})
        node = {
            :instance   => instance,
            :definition => instance.definition,
            :parent     => parent,
            :children   => [],
            :world      => world,
            :local      => instance.transformation,
            :signature  => nil,
            :class_key  => nil,
            :live       => nil,                                               # <-- The instance it is, once found again in the walk
            :final      => nil,                                               # <-- The definition it ends up on
            :payload    => payload
        }

        (parent ? parent[:children] : plan[:roots]) << node
        (plan[:by_def][node[:definition]] ||= []) << node unless payload[:role] == :place
        node
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Local Move as Whole Numbers, for Comparing Copies
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Quantise(vector)
        q = NA_DEEP_UNIQUE_QUANTUM
        [(vector.x.to_f / q).round, (vector.y.to_f / q).round, (vector.z.to_f / q).round]
    end
    # ---------------------------------------------------------------

    # FUNCTION | A World Vector in an Instance's Own Axes
    # ------------------------------------------------------------
    # Two points through the inverse rather than the bare vector, the rule
    # the deep tools keep: a direction is a difference of positions. Through
    # a scaled instance the local vector comes out longer or shorter by the
    # scale, which is what lands a vertex the right WORLD distance away.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__LocalVector(world, vector)
        inverse = world.inverse
        origin  = Geom::Point3d.new(0, 0, 0)

        (origin + vector).transform(inverse) - origin.transform(inverse)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Count Points Toward the Signing Budget; False Once It Is Spent
    # ------------------------------------------------------------
    # A signature that would cost more than the budget is not worked out: the
    # copy signs as itself (Na__DeepUnique__Alone), which only ever splits
    # copies apart, never joins two that differ.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Spend(plan, points)
        return false if plan[:work] + points > NA_DEEP_UNIQUE_MAX_WORK

        plan[:work] += points
        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Signature of a Copy That Shares With Nothing
    # ------------------------------------------------------------
    # Keyed by the instance, not the node: two paths through one instance
    # (it sits in a container that has copies) are the same copy.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Alone(node)
        [:alone, node[:instance].entityID]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does More Than One Node Use This Node's Definition?
    # ------------------------------------------------------------
    # Only then can two copies be compared, so only then is a costly
    # signature worth working out.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Shared?(plan, node)
        (plan[:by_def][node[:definition]] || []).length > 1
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Occurrences
    # -----------------------------------------------------------------------------

    # FUNCTION | How Many Places in the Whole Model a Definition Shows
    # ------------------------------------------------------------
    # A copy in the model root shows once; a copy inside another definition
    # shows once for every place that one shows; a copy inside a definition
    # nothing places shows nowhere. ComponentDefinition#instances lists
    # instance OBJECTS, not placements (one object in a group placed three
    # times is one entry), so the placements are counted up through the
    # parents here: what count_used_instances describes, in a form the
    # offline doubles can prove.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Occurrences(definition, memo)
        return memo[definition] if memo.key?(definition)

        memo[definition] = 0                                                  # <-- A guard only: SketchUp forbids a definition inside itself
        total = 0

        definition.instances.each do |instance|
            parent = instance.parent
            total += parent.is_a?(Sketchup::ComponentDefinition) ? Na__NobleDrawingTools.Na__DeepUnique__Occurrences(parent, memo) : 1
        end

        memo[definition] = total
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Places the User's Open Context Shows
    # ------------------------------------------------------------
    # Everything inside an open component with three copies shows three
    # times, and editing it changes all three: SketchUp's own rule for an
    # open component, which a deep edit inside it keeps.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__ContextOccurrences(plan)
        path = Array(plan[:model].active_path)
        return 1 if path.empty?

        count = Na__NobleDrawingTools.Na__DeepUnique__Occurrences(path.last.definition, plan[:memo])
        count < 1 ? 1 : count
    rescue StandardError
        1
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Deciding
    # -----------------------------------------------------------------------------

    # FUNCTION | The Key a Node Is Grouped By
    # ------------------------------------------------------------
    # Its signature; a group's carries the group itself as well (GROUPS in
    # the header), so no two groups are ever asked to share.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__ClassKey(node)
        instance = node[:instance]
        return [:group, instance.entityID, node[:signature]] if instance.is_a?(Sketchup::Group)

        node[:signature]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Decide, on Paper, What Becomes of Each Definition
    # ------------------------------------------------------------
    # Every node's signature must be set first. Sets plan[:refused] to the
    # first reason nothing may change, or fills plan[:decisions]:
    #   :keep     the class key that keeps the definition, or nil when every
    #             class has to move off it
    #   :outside  occurrences the edit does not reach
    #   :nodes    the nodes using it; :classes  how many signatures among them
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Decide(plan)
        plan[:mult] = Na__NobleDrawingTools.Na__DeepUnique__ContextOccurrences(plan)

        plan[:by_def].each do |definition, nodes|
            refusal = Na__NobleDrawingTools.Na__DeepUnique__Refusal(definition)
            locked  = nodes.find { |node| node[:instance].respond_to?(:locked?) && node[:instance].locked? }
            refusal ||= "#{Na__NobleDrawingTools.Na__DeepUnique__Name(locked[:instance])} is locked — unlock it to change what is inside it" if locked

            if refusal
                plan[:refused] = refusal
                return plan
            end

            counts = {}
            nodes.each do |node|
                node[:class_key]         = Na__NobleDrawingTools.Na__DeepUnique__ClassKey(node)
                counts[node[:class_key]] = (counts[node[:class_key]] || 0) + 1
            end

            outside = Na__NobleDrawingTools.Na__DeepUnique__Occurrences(definition, plan[:memo]) - (nodes.length * plan[:mult])
            keep    = nil

            if outside <= 0                                                   # <-- Nothing outside the edit: the biggest class stays put
                best = 0
                counts.each do |key, count|
                    next unless count > best                                  # <-- Ties go to the class planned first

                    keep = key
                    best = count
                end
            end

            plan[:decisions][definition] = {
                :keep    => keep,
                :outside => outside > 0 ? outside : 0,
                :nodes   => nodes.length,
                :classes => counts.length
            }
        end

        plan
    end
    # ---------------------------------------------------------------

    # FUNCTION | Will Settling These Nodes Change the Model?
    # ------------------------------------------------------------
    # False when every one keeps its definition: then they are only found
    # again, which needs no open context and no operation.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__NeedsSettle?(plan, nodes)
        (nodes || []).any? do |node|
            next false if node[:payload][:role] == :place

            decision = plan[:decisions][node[:definition]]
            decision.nil? || decision[:keep] != node[:class_key]
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Finding a Planned Copy Again
    # -----------------------------------------------------------------------------

    # FUNCTION | Is This Collection's Owner Open, So That It Reports World?
    # ------------------------------------------------------------
    # The model root is a parent of every context; a definition is open while
    # one of the instances on the active path is a copy of it.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__OwnerOpen?(model, owner)
        return true if owner.is_a?(Sketchup::Model)

        Array(model.active_path).any? { |instance| instance.definition == owner }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Do Two Transformations Place Something in the Same Spot?
    # ------------------------------------------------------------
    def self.Na__DeepUnique__SamePlace?(a, b)
        x = a.to_a
        y = b.to_a

        x.each_index.all? { |i| (x[i].to_f - y[i].to_f).abs <= NA_DEEP_UNIQUE_PLACE_TOL * (1.0 + y[i].to_f.abs) }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Find Each Planned Copy in a Collection as It Stands Now
    # ------------------------------------------------------------
    # A node whose instance still stands in `entities` is that instance. One
    # whose container has since been settled onto a new definition stands in
    # the copy instead: same definition, same place. Compared with what was
    # read for it in the same space when planned: world while the collection
    # is open, its own transformation while closed. Returns node => instance;
    # a node with no match is left out.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Rebind(plan, nodes, entities)
        owner = entities.parent
        open  = Na__NobleDrawingTools.Na__DeepUnique__OwnerOpen?(plan[:model], owner)
        bound = {}
        taken = {}
        pool  = nil

        nodes.each do |node|
            instance = node[:instance]

            if instance.valid? && instance.parent == owner
                bound[node]     = instance
                taken[instance] = true
                next
            end

            pool ||= entities.select { |entity| Na__NobleDrawingTools.Na__DeepUnique__Instance?(entity) }
            wanted = open ? node[:world] : node[:local]

            match = pool.find do |candidate|
                next false if taken[candidate]
                next false unless candidate.definition == node[:definition]

                Na__NobleDrawingTools.Na__DeepUnique__SamePlace?(candidate.transformation, wanted)
            end
            next unless match

            bound[node]  = match
            taken[match] = true
        end

        bound
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Settling
    # -----------------------------------------------------------------------------

    # FUNCTION | Settle the Planned Copies Standing in One Collection
    # ------------------------------------------------------------
    # `nodes` stand in `entities` — the user's own context, or the
    # representative just opened — and must be closed. Each is found again
    # there, then moved onto its final definition as decided. `hook` is
    # called as hook.call(before, after) after every make_unique, for data a
    # tool keeps on its definitions. Inside the caller's operation.
    #
    # Returns the nodes to open next: the first copy of each final definition
    # (a node whose final definition already has one rides on its edit, and
    # is counted in plan[:riders]). :place nodes are only found again.
    # Raises, naming the object, when a copy cannot be found or will not part.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__SettleIn(plan, nodes, entities, hook = nil)
        return [] if nodes.nil? || nodes.empty?

        bound   = Na__NobleDrawingTools.Na__DeepUnique__Rebind(plan, nodes, entities)
        missing = nodes.find { |node| bound[node].nil? }
        if missing
            raise ArgumentError, "#{Na__NobleDrawingTools.Na__DeepUnique__Name(missing[:instance])} could not be found again after the group round it was made unique"
        end

        nodes.each { |node| node[:live] = bound[node] }
        reps = []

        Na__NobleDrawingTools.Na__DeepUnique__Classes(nodes).each do |definition, key, members|
            if members.first[:payload][:role] == :place
                members.each { |node| node[:final] = node[:live].definition; reps << node }
                next
            end

            decision = plan[:decisions][definition] || { :keep => nil }

            if decision[:keep] == key
                stray = members.find { |node| !node[:live].definition.equal?(definition) }
                raise ArgumentError, "#{Na__NobleDrawingTools.Na__DeepUnique__Name(stray[:live])} changed under the edit — nothing more was done" if stray
            else
                Na__NobleDrawingTools.Na__DeepUnique__Isolate(plan, definition, key, members.map { |node| node[:live] }.uniq, hook)
            end

            members.each do |node|
                final        = node[:live].definition
                node[:final] = final

                if plan[:finals].key?(final)
                    plan[:riders][final] += 1
                else
                    plan[:finals][final] = node
                    reps << node
                end
            end
        end

        reps
    end
    # ---------------------------------------------------------------

    # FUNCTION | Nodes by Definition, Then by Class, in the Order Planned
    # ------------------------------------------------------------
    # Returns [[definition, class key, [nodes]], ...]. :place nodes form
    # classes of their own, by node.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Classes(nodes)
        order  = []
        groups = {}

        nodes.each do |node|
            key   = node[:payload][:role] == :place ? [:place, node.object_id] : node[:class_key]
            label = [node[:definition], key]

            unless groups.key?(label)
                groups[label] = []
                order << label
            end

            groups[label] << node
        end

        order.map { |label| [label[0], label[1], groups[label]] }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Give a Set of Copies One Definition of Their Own
    # ------------------------------------------------------------
    # The first component is made unique, the rest are moved onto what it
    # got. The definition made is remembered for its class, so copies of the
    # class met later, under another container, join it rather than make
    # another. A group cannot be handed a definition, so a group is made
    # unique on its own (it is a class of its own anyway).
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Isolate(plan, definition, key, instances, hook)
        target = plan[:registry][[definition, key]]

        instances.each do |instance|
            next if target && instance.definition.equal?(target)                 # <-- Met twice: already there

            unless instance.definition.equal?(definition)
                raise ArgumentError, "#{Na__NobleDrawingTools.Na__DeepUnique__Name(instance)} changed under the edit — nothing more was done"
            end

            if target && Na__NobleDrawingTools.Na__DeepUnique__Component?(instance)
                Na__NobleDrawingTools.Na__DeepUnique__Join(instance, target)
                plan[:joined] += 1
                next
            end

            made = Na__NobleDrawingTools.Na__DeepUnique__MakeUnique(plan, instance, hook)
            plan[:made] += 1
            next unless Na__NobleDrawingTools.Na__DeepUnique__Component?(instance)

            target ||= made
            plan[:registry][[definition, key]] ||= made
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Make One Copy Unique, and Check It Was This One
    # ------------------------------------------------------------
    # Returns the definition it now has. Refuses a copy that is already the
    # only one of its definition: the plan said it shares, so something is
    # not as planned, and editing on would change what it should not.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__MakeUnique(plan, instance, hook)
        before = instance.definition
        others = before.instances.reject { |other| other.equal?(instance) }

        if others.empty?
            raise ArgumentError, "#{Na__NobleDrawingTools.Na__DeepUnique__Name(instance)} could not be parted from its copies elsewhere"
        end

        instance.make_unique
        after = instance.definition
        after = Na__NobleDrawingTools.Na__DeepUnique__Repair(plan, instance, before, others) if after.equal?(before)

        hook.call(before, after) if hook
        after
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put Right a make_unique That Gave Another Copy the New Definition
    # ------------------------------------------------------------
    # #952: the copy asked keeps the old definition and another one gets the
    # new. Between components that is undone with definition=: the other copy
    # back onto the old definition, this one onto the new.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Repair(plan, instance, before, others)
        moved = others.find { |other| other.valid? && !other.definition.equal?(before) }

        if moved && Na__NobleDrawingTools.Na__DeepUnique__Component?(instance) && Na__NobleDrawingTools.Na__DeepUnique__Component?(moved)
            fresh               = moved.definition
            moved.definition    = before
            instance.definition = fresh

            if instance.definition.equal?(fresh) && moved.definition.equal?(before)
                plan[:repaired] += 1
                return fresh
            end
        end

        raise ArgumentError, "SketchUp would not make #{Na__NobleDrawingTools.Na__DeepUnique__Name(instance)} unique"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Move a Component Onto a Definition, and Check It Moved
    # ------------------------------------------------------------
    # definition= keeps the instance's transformation (ruby.sketchup.com) and
    # answers false when it fails, so the definition is read back.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Join(instance, target)
        instance.definition = target
        return target if instance.definition.equal?(target)

        raise ArgumentError, "SketchUp would not move #{Na__NobleDrawingTools.Na__DeepUnique__Name(instance)} onto its new definition"
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Walking From Context to Context
    # -----------------------------------------------------------------------------

    # FUNCTION | Open One Context; True Only Once It Really Is the Open One
    # ------------------------------------------------------------
    # active_path= raises for a locked or invalid path, for a Live Component,
    # and when another copy of a definition on the path is locked
    # (ruby.sketchup.com), and is refused inside an open operation, so this
    # is only ever called between operations. Straight from one context to
    # the next: going back out in between would be an undo step of its own.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Enter(model, path)
        return true if Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, path)

        model.active_path = path
        Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, path)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Put the User Back Where They Were; True If the Context Changed
    # ------------------------------------------------------------
    # Falls back to the model root rather than ever leaving them inside a
    # copy the walk opened.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Restore(model, previous)
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
    # ------------------------------------------------------------
    # Only on a walk that stopped before its first context opened: an edit
    # with nothing in it joins the step left waiting, so the user's next
    # action does not silently become part of it (Deep Scale's ClosePending).
    # ------------------------------------------------------------
    def self.Na__DeepUnique__ClosePending(model, name)
        model.start_operation(name, true, false, true)
        model.commit_operation
        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Pick-and-Edit Tools: Settle Before the Edit (5.2.44)
    # -----------------------------------------------------------------------------

    # FUNCTION | Settle the Copies a Set of Deep Picks Sits In, Before They Are Edited
    # ------------------------------------------------------------
    # For the tools that edit what was picked — a face (Deep Push/Pull, Deep
    # Project), an edge (the edge tools), a quad line — each reached by an
    # ABSOLUTE path (DeepPick's target hash). `sign` answers each target's own
    # signature: what its edit does to its definition, read in that
    # definition's axes (nil: the target's copy shares with nothing). Copies
    # picked alike stay one definition; copies the picks do not reach keep
    # theirs. The tool's commit then runs as it always has, on the targets
    # handed back. Returns
    #   :refused   why nothing may change, or nil
    #   :targets   one per target, in order: the target as it stands now (its
    #              :path, and :face / :edge / :faces / :edges / :vertices moved
    #              onto the copy it now sits in), or nil when its copy rides on
    #              an earlier target's edit: the same edit, made once
    #   :home      the user's own context, where the tool puts them back
    #   :pending   true when copies were settled: the last operation here left
    #              next_transparent set, so the tool's own context entry joins
    #              this undo step, and its edit must start transparent
    #   :selected  the selection before anything opened (opening clears it)
    #   :riders    targets dropped as riders; :plan for the report
    # When every copy keeps its definition nothing changes, :pending is false
    # and the targets come back as they went in.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__SettleTargets(model, targets, op_name, sign = nil)
        home   = Array(model.active_path)
        plan   = Na__NobleDrawingTools.Na__DeepUnique__NewPlan(model)
        result = {
            :refused  => nil,
            :targets  => targets.dup,
            :home     => model.active_path,
            :pending  => false,
            :selected => Na__NobleDrawingTools.Na__DeepPick__FocusSnapshot(model),
            :riders   => 0,
            :plan     => plan
        }
        leaves = Na__NobleDrawingTools.Na__DeepUnique__PlanTargets(plan, targets, home, sign)

        unless leaves
            result[:refused] = 'the editing context changed since the pick — pick it again'
            return result
        end

        return result if plan[:roots].empty?                                   # <-- Every pick in the user's own context: nothing shared to settle

        plan[:roots].each { |root| Na__NobleDrawingTools.Na__DeepUnique__SignTree(root) }
        Na__NobleDrawingTools.Na__DeepUnique__Decide(plan)

        if plan[:refused]
            result[:refused] = plan[:refused]
            return result
        end

        # Every copy keeping its definition changes nothing, but the same pick
        # on several copies is still ONE edit: the copies are walked closed,
        # only read, so the riders are found (an edge cut through one copy is
        # gone from the rest before their turn: "an edge vanished mid-batch").
        if Na__NobleDrawingTools.Na__DeepUnique__AnySettle?(plan)
            failed, pending = Na__NobleDrawingTools.Na__DeepUnique__SettleChain(model, plan, home, op_name)
        else
            failed, pending = Na__NobleDrawingTools.Na__DeepUnique__ReadChain(model, plan), false
        end

        failed ||= Na__NobleDrawingTools.Na__DeepUnique__Rebound(plan, targets, leaves, home, result)
        result[:pending] = pending

        if failed
            if pending                                                         # <-- Close the step left waiting, and put the user back
                restored = Na__NobleDrawingTools.Na__DeepUnique__Restore(model, result[:home])
                Na__NobleDrawingTools.Na__DeepUnique__ClosePending(model, op_name) unless restored
                Na__NobleDrawingTools.Na__DeepPick__FocusRestore(model, result[:selected])
            end

            result[:pending] = false
            result[:refused] = pending ? "#{failed} — Ctrl+Z takes back the copies made unique" : failed
        end

        result
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Node per Path Below the User's Context; Returns Each Target's Node
    # ------------------------------------------------------------
    # nil for a target in the user's own context. nil overall when a path no
    # longer starts with the user's context: the pick belongs to another one.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__PlanTargets(plan, targets, home, sign)
        nodes  = {}
        leaves = []

        targets.each_with_index do |target, index|
            path = Na__NobleDrawingTools.Na__DeepPick__Instances(target[:path])
            return nil unless path.length >= home.length && home.each_with_index.all? { |instance, i| instance == path[i] }

            below = path[home.length..-1] || []

            if below.empty?
                leaves << nil
                next
            end

            parent = nil
            key    = nil

            below.each do |instance|
                key  = key ? "#{key}/#{instance.entityID}" : instance.entityID.to_s
                node = nodes[key]

                unless node
                    world      = parent ? parent[:world] * instance.transformation : instance.transformation
                    node       = Na__NobleDrawingTools.Na__DeepUnique__AddNode(plan, instance, parent, world, { :items => [] })
                    nodes[key] = node
                end

                parent = node
            end

            parent[:payload][:items] << [index, sign ? sign.call(target) : nil]
            leaves << parent
        end

        leaves
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Sign a Node by Its Picks and Everything Below It
    # ------------------------------------------------------------
    # A pick with no signature makes its copy share with nothing. Sorted by
    # hash: two copies whose picks are the same set read the same; a
    # collision could only ever split two copies, never join them.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__SignTree(node)
        node[:children].each { |child| Na__NobleDrawingTools.Na__DeepUnique__SignTree(child) }

        items = node[:payload][:items].map { |_index, signature| signature }

        if items.include?(nil)
            node[:signature] = Na__NobleDrawingTools.Na__DeepUnique__Alone(node)
            return
        end

        below = node[:children].map { |child| [child[:instance].entityID, child[:signature]] }.sort_by(&:first)
        node[:signature] = [items.sort_by(&:hash), below]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does Any Copy Have to Move Off Its Definition?
    # ------------------------------------------------------------
    def self.Na__DeepUnique__AnySettle?(plan)
        plan[:by_def].any? do |definition, nodes|
            decision = plan[:decisions][definition]
            decision.nil? || nodes.any? { |node| decision[:keep] != node[:class_key] }
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Settle Top-Down, Each Level in Its Container's Open Context
    # ------------------------------------------------------------
    # The copies in the user's context first, in an operation that leaves
    # next_transparent set. Then each representative whose own copies have to
    # move is opened straight from the last (each entry pulled into the step)
    # and settled inside it; one whose copies all keep their definition is
    # only read, closed. The walk ends in the last container it opened, or in
    # the user's context: the tool opens its pick's context from there.
    # Returns [why it stopped or nil, whether a next_transparent is waiting].
    # The first operation is not transparent, so a failure in it is aborted
    # cleanly and nothing is left waiting.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__SettleChain(model, plan, home, op_name)
        model.start_operation(op_name, true, true, false)                      # <-- next_transparent: what comes next joins this step

        begin
            queue = Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, plan[:roots], model.active_entities)
        rescue StandardError => error
            model.abort_operation
            return [error.message, false]
        end

        model.commit_operation

        until queue.empty?
            node = queue.shift
            next if node[:children].empty?

            unless Na__NobleDrawingTools.Na__DeepUnique__NeedsSettle?(plan, node[:children])
                begin
                    queue.concat(Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, node[:children], node[:live].definition.entities))
                rescue StandardError => error
                    return [error.message, true]
                end

                next
            end

            unless Na__NobleDrawingTools.Na__DeepUnique__Enter(model, home + Na__NobleDrawingTools.Na__DeepUnique__LivePath(node))
                return ["#{Na__NobleDrawingTools.Na__DeepUnique__Name(node[:live])} would not open for its copies to be made unique", true]
            end

            model.start_operation(op_name, true, true, true)                   # <-- Joins the entry just made, pulls in the next
            failed = nil

            begin
                queue.concat(Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, node[:children], model.active_entities))
            rescue StandardError => error
                failed = error.message
            end

            model.commit_operation                                             # <-- Never abort a transparent operation
            return [failed, true] if failed
        end

        [nil, true]
    end
    # ---------------------------------------------------------------

    # FUNCTION | Walk the Copies Without Changing Anything; nil or Why Not
    # ------------------------------------------------------------
    # For a plan where every copy keeps its definition: each node found where
    # it stands and given its final definition (its own), so the riders are
    # known. No operation, no context opened.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__ReadChain(model, plan)
        queue = Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, plan[:roots], model.active_entities)

        until queue.empty?
            node = queue.shift
            next if node[:children].empty?

            queue.concat(Na__NobleDrawingTools.Na__DeepUnique__SettleIn(plan, node[:children], node[:live].definition.entities))
        end

        nil
    rescue StandardError => error
        error.message
    end
    # ---------------------------------------------------------------

    # FUNCTION | Each Target as It Stands After the Settle; nil or Why Not
    # ------------------------------------------------------------
    # Fills result[:targets]. A target whose copy rides on an earlier one's
    # edit becomes nil. One whose definition was replaced is moved onto the
    # copy: its entities are found in the new definition by their own local
    # geometry (both definitions are closed now, so both report local, and an
    # exact copy matches exactly).
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Rebound(plan, targets, leaves, home, result)
        indexes = {}

        targets.each_with_index do |target, index|
            leaf = leaves[index]
            next unless leaf

            unless Na__NobleDrawingTools.Na__DeepUnique__Leads?(plan, leaf)
                result[:targets][index] = nil
                result[:riders] += 1
                next
            end

            moved = target.merge(:path => home + Na__NobleDrawingTools.Na__DeepUnique__LivePath(leaf))

            unless leaf[:final].equal?(leaf[:definition])
                index_of = (indexes[leaf[:final]] ||= Na__NobleDrawingTools.Na__DeepUnique__ShapeIndex(leaf[:final]))
                moved    = Na__NobleDrawingTools.Na__DeepUnique__MoveEntities(moved, index_of)
                return "a pick in #{Na__NobleDrawingTools.Na__DeepUnique__Name(leaf[:live])} could not be found again in its new copy" unless moved
            end

            if moved.key?(:shared_count)
                moved[:shared_count] = Na__NobleDrawingTools.Na__DeepPick__SharedInstanceCount(moved[:path])
            end

            result[:targets][index] = moved
        end

        # The first copy of anything is the one it is edited through, so a
        # set of picks that came back all riders was never read: say so
        # rather than hand the tool nothing to edit.
        nested = targets.each_index.select { |index| leaves[index] }
        return 'the copies picked could not be read' if !nested.empty? && nested.none? { |index| result[:targets][index] }

        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is Every Node on This Pick's Way Down the One Its Definition Is Edited Through?
    # ------------------------------------------------------------
    # A node below a copy that rides on another was never walked (no :final):
    # its picks are that other copy's picks.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Leads?(plan, leaf)
        node = leaf

        while node
            return false unless node[:final] && plan[:finals][node[:final]].equal?(node)

            node = node[:parent]
        end

        true
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Definition's Faces, Edges and Vertices, Keyed by Their Local Geometry
    # ------------------------------------------------------------
    def self.Na__DeepUnique__ShapeIndex(definition)
        index = {}

        definition.entities.each do |entity|
            next unless entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)

            index[Na__NobleDrawingTools.Na__DeepUnique__Shape(entity)] ||= entity

            next unless entity.is_a?(Sketchup::Edge)

            entity.vertices.each { |vertex| index[Na__NobleDrawingTools.Na__DeepUnique__Shape(vertex)] ||= vertex }
        end

        index
    end
    # ---------------------------------------------------------------

    # FUNCTION | An Entity's Local Geometry as a Key
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Shape(entity)
        cell = lambda do |point|
            q = NA_DEEP_UNIQUE_QUANTUM
            [(point.x.to_f / q).round, (point.y.to_f / q).round, (point.z.to_f / q).round]
        end

        case entity
        when Sketchup::Vertex then [:vertex, cell.call(entity.position)]
        when Sketchup::Edge   then [:edge, entity.vertices.map { |vertex| cell.call(vertex.position) }.sort]
        when Sketchup::Face   then [:face, entity.vertices.map { |vertex| cell.call(vertex.position) }.sort]
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Target's Entities Moved Onto Their Copies; nil If One Is Missing
    # ------------------------------------------------------------
    # The keys DeepPick's targets and the quad line carry: :face, :edge,
    # :faces, :edges, :vertices. An edge's :faces and :face_count are read
    # again from the edge found, as BuildEdgeTarget reads them.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__MoveEntities(target, index)
        moved = target.dup
        find  = lambda { |entity| entity && entity.valid? ? index[Na__NobleDrawingTools.Na__DeepUnique__Shape(entity)] : nil }

        [:face, :edge].each do |key|
            next unless moved[key]

            moved[key] = find.call(moved[key])
            return nil unless moved[key]
        end

        [:faces, :edges, :vertices].each do |key|
            next unless moved[key].is_a?(Array)

            moved[key] = moved[key].map { |entity| find.call(entity) }
            return nil if moved[key].include?(nil)
        end

        if moved[:edge] && target.key?(:faces)
            moved[:faces]      = moved[:edge].faces
            moved[:face_count] = moved[:faces].length
        end

        moved
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open a Pick's Context, After a Settle or Without One
    # ------------------------------------------------------------
    # For the commits that open their own context (Deep Push/Pull, its Joint
    # surfaces, Deep Project): the operation flags and the context to go back
    # to, so the settle, the entry, the edit and the way back are ONE undo
    # step. Without a settle it answers exactly what those commits always
    # did: transparent both ways when a context was entered, plain otherwise.
    # Returns { :entered, :previous, :transparent, :next_transparent, :leaving }.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__OpenFor(model, target_path, settle)
        current  = model.active_path
        pending  = settle ? settle[:pending] : false
        previous = pending ? settle[:home] : current
        entered  = false

        unless Na__NobleDrawingTools.Na__DeepPick__SameContext?(current, target_path)
            begin
                model.active_path = target_path
                entered = true
            rescue StandardError
                entered = false
            end
        end

        here    = entered ? target_path : current
        leaving = !Na__NobleDrawingTools.Na__DeepPick__SameContext?(here, previous)

        { :entered => entered, :previous => previous, :transparent => entered || pending, :next_transparent => leaving, :leaving => leaving }
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Orientation and Scale a Copy Is Placed With, as a Key
    # ------------------------------------------------------------
    # For edits whose shape may follow the world's directions (a profile
    # with a top and a bottom): copies placed alike, moved but not turned,
    # scaled or mirrored, read them alike.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__PlacementKey(transformation)
        values = (transformation || Geom::Transformation.new).to_a
        [0, 1, 2, 4, 5, 6, 8, 9, 10].map { |i| (values[i].to_f / 1e-6).round }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Saying What Happened
    # -----------------------------------------------------------------------------

    # FUNCTION | The Live Path From the User's Context Down to a Node
    # ------------------------------------------------------------
    # Every node above a representative is a representative itself, so each
    # has been found again (:live) by the time this is asked.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__LivePath(node)
        chain = []
        while node
            chain.unshift(node[:live] || node[:instance])
            node = node[:parent]
        end
        chain
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Copies Took Part in a Representative's Edit
    # ------------------------------------------------------------
    def self.Na__DeepUnique__CopiesOf(plan, node)
        final = node[:final]
        final ? 1 + plan[:riders][final] : 1
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Words for the Status Line
    # ------------------------------------------------------------
    # The definition with the most copies in the edit speaks for the rest:
    # "30 copies of Baluster changed as one", and, when copies elsewhere
    # were kept apart, how many. New definitions are counted. "" when the
    # edit touched nothing shared.
    # ------------------------------------------------------------
    def self.Na__DeepUnique__Report(plan)
        return '' unless plan

        best = nil
        plan[:decisions].each do |definition, decision|
            next if decision[:nodes] < 2 && decision[:outside].zero?

            score = [decision[:nodes], decision[:outside]]
            best  = [definition, decision] if best.nil? || (score <=> [best[1][:nodes], best[1][:outside]]) > 0
        end

        parts = []

        if best
            definition, decision = best
            name   = Na__NobleDrawingTools.Na__DeepUnique__Name(definition)
            copies = decision[:nodes] * plan[:mult]
            parts << "#{copies} copies of #{name} changed #{decision[:classes] == 1 ? 'as one' : "in #{decision[:classes]} sets"}" if copies > 1
            parts << "#{decision[:outside]} other cop#{decision[:outside] == 1 ? 'y' : 'ies'} kept as #{decision[:outside] == 1 ? 'it was' : 'they were'}" if decision[:outside] > 0
        end

        made = plan[:made]
        parts << "#{made} new definition#{made == 1 ? '' : 's'}" if made > 0
        parts.join(', ')
    rescue StandardError
        ''
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP UNIQUE MODULE
# =============================================================================
