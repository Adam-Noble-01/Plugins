# =============================================================================
# NA INSERT PRIMATIVES - DRAWN SUBTRACT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnSubtract__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Cut a drawn box out of every solid inside a picked group
# CREATED    : 2026
#
# DESCRIPTION:
# - The Drawn Volume tool's Subtraction option ends here. It hands over a box
#   described in WORLD space — anchor, plane, width, height, depth — plus the
#   instance the user clicked, and this builds a cutter and runs it through
#   Sketchup::Group#subtract against every solid inside that instance.
# - Solid tools are SketchUp Pro only. Na__Subtract__Available? is checked
#   before the tool ever offers the stage, so a Make user gets a plain message
#   rather than a NoMethodError mid-drag.
#
# TWO PIPELINES, CHOSEN BY WHAT IS IN THE GROUP:
# - SIMPLE — the picked group holds no child groups or components. There is one
#   candidate and one question: is it a solid? Yes, cut it. No, and the tool
#   says "Selection Not Solid" on a red overlay instead of a blue one.
# - DEEP — the picked group holds children. Every descendant is walked and each
#   solid one is cut; a solid is NOT descended into, because cutting the shell
#   is cutting everything it stands for. Nothing solid anywhere below, and the
#   same red overlay appears reading "No Solid Children".
# - The parent is the fallback in both: a group that holds children AND is
#   itself a watertight shell is cut when none of its children are solids.
#
# WHY EACH SOLID IS CUT INSIDE ITS OWN EDITING CONTEXT:
# - Sketchup::Group#subtract needs both operands in the SAME entities
#   collection, so the cutter has to be built beside the solid it cuts, at
#   whatever depth that is. Editing a definition's entities from outside the
#   editing context leaves the model right and the display cache stale — the
#   saga the push tool was cured of, written up in the 5.0 devlog. So victims
#   are grouped by the collection they live in and each collection is OPENED,
#   through the same Na__DeepPick__ExecuteInContext every other deep edit here
#   uses. Inside an open context every coordinate is global (the rule in the
#   DeepPick hub header), which is exactly the space the box arrives in: the
#   cutter needs no conversion at all.
# - The context is ASSERTED inside the block rather than assumed. If SketchUp
#   refuses to open it the victims in that batch are reported as skipped —
#   building world geometry into a closed definition would silently put the
#   opening somewhere else in the model, which is far worse than not cutting.
#
# THE OPERAND ORDER — THE CUTTER IS THE RECEIVER (researched 17-Sep-2026):
# - Sketchup::Group#subtract is documented in two places that CONTRADICT each
#   other, and 5.1.3 shipped believing the wrong one:
#     summary  "the boolean difference of the two groups ... (this - arg)"
#     @param   "group — The group to subtract THIS GROUP FROM"   <= arg - this
#   The @param is the one that matches reality. Two independent checks agree
#   with it: #trim, the non-destructive sibling, documents that "the original
#   GROUP2 is erased and a newly trimmed version is created" — the ARGUMENT is
#   the thing being cut and the receiver survives as the tool; and SketchUp's
#   own Solid Tools UI states "the first solid you select is your cutting tool".
# - So it is  cutter.subtract(victim)  and the result is victim MINUS cutter.
#   Written the other way round, a window-sized cutter wholly inside a wall
#   computes cutter - wall, which is empty — and an empty result takes BOTH
#   operands with it. That is not a failed cut, it is the wall gone, which is
#   precisely what 5.1.3 did.
#
# AND BECAUSE THE DOCUMENTATION CANNOT BE TRUSTED, THE RESULT IS CHECKED:
# - Every cut runs inside an operation that is still open, so a boolean that
#   destroys the solid without producing a replacement is ABORTED rather than
#   committed. A wrong order, a future API change or a degenerate solid can
#   therefore cost a status-bar message and nothing else.
# - A full removal is only accepted as intentional when the solid genuinely
#   sits inside the cutter, which is the one case where "nothing left" is the
#   right answer.
#
# WHAT SURVIVES THE BOOLEAN:
# - subtract consumes both operands and hands back a NEW container, so the
#   solid's name, tag, material, shadow flags and attribute dictionaries are
#   read off it first and written onto the result. Without that, cutting a
#   window out of a wall renames the wall to "Group#417" and drops its tag.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnGridSnap__'
require_relative 'Na__InsertPrimatives__DrawnGeometry__'
require_relative 'Na__InsertPrimatives__DrawnDeepPick__Instance__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Subtract Constants
    # -----------------------------------------------------------------------------

    NA_SUBTRACT_CUTTER_NAME  = '01__DrawnVolume__Cutter'.freeze
    NA_SUBTRACT_OPERATION    = 'Subtract Drawn Volume'.freeze

    NA_SUBTRACT_MAX_DEPTH    = 12                                             # <-- Deeper than any real assembly; a guard on a cycle
    NA_SUBTRACT_MAX_NODES    = 4_000                                          # <-- Ceiling on a full collect
    NA_SUBTRACT_PROBE_NODES  = 400                                            # <-- Ceiling on the hover probe, which runs every frame

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Edition Capability
    # -----------------------------------------------------------------------------

    # FUNCTION | Does This SketchUp Have the Solid Tools?
    # ------------------------------------------------------------
    def self.Na__Subtract__Available?
        Sketchup::Group.method_defined?(:subtract)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Entity a Watertight Solid?
    # ------------------------------------------------------------
    def self.Na__Subtract__Solid?(entity)
        return false unless entity && entity.valid?
        return false unless entity.respond_to?(:manifold?)

        entity.manifold?
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Group and Component Children of an Instance
    # ------------------------------------------------------------
    def self.Na__Subtract__ChildInstances(instance)
        return [] unless instance && instance.valid?
        return [] unless instance.respond_to?(:definition) && instance.definition

        instance.definition.entities.select do |entity|
            entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        end
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Hover Survey
    # -----------------------------------------------------------------------------

    # FUNCTION | Can This Instance Be Cut, and Which Pipeline Would Do It?
    # ------------------------------------------------------------
    # Runs on every mouse move while the target stage is live, so it answers
    # the moment it knows: the deep walk stops at the FIRST solid it meets
    # rather than counting them all. The real count is reported at commit,
    # where the walk has to happen anyway.
    #
    # Returns { :pipeline, :valid, :headline, :detail }.
    # ------------------------------------------------------------
    def self.Na__Subtract__Survey(target)
        return Na__InsertPrimatives.Na__Subtract__SurveyResult(:none, false, 'No Selection', 'Hover a group or component') unless target

        instance = target[:instance]
        return Na__InsertPrimatives.Na__Subtract__SurveyResult(:none, false, 'Selection Gone', 'That object no longer exists') unless instance && instance.valid?

        cached = Na__InsertPrimatives.Na__Subtract__CachedSurvey(instance)
        return cached if cached

        children = Na__InsertPrimatives.Na__Subtract__ChildInstances(instance)

        survey =
            if children.empty?
                if Na__InsertPrimatives.Na__Subtract__Solid?(instance)
                    Na__InsertPrimatives.Na__Subtract__SurveyResult(:simple, true, 'Solid', 'Click to cut this solid')
                else
                    Na__InsertPrimatives.Na__Subtract__SurveyResult(:simple, false, 'Selection Not Solid', 'Nothing here is watertight')
                end
            elsif Na__InsertPrimatives.Na__Subtract__AnySolidBelow?(instance, children)
                Na__InsertPrimatives.Na__Subtract__SurveyResult(:deep, true, 'Nested Solids', 'Click to cut every solid inside')
            elsif Na__InsertPrimatives.Na__Subtract__Solid?(instance)
                Na__InsertPrimatives.Na__Subtract__SurveyResult(:deep, true, 'Solid Parent', 'No solid children — the parent shell will be cut')
            else
                Na__InsertPrimatives.Na__Subtract__SurveyResult(:deep, false, 'No Solid Children', 'Nothing inside is watertight')
            end

        Na__InsertPrimatives.Na__Subtract__StoreSurvey(instance, survey)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build One Survey Answer
    # ------------------------------------------------------------
    def self.Na__Subtract__SurveyResult(pipeline, valid, headline, detail)
        {
            :pipeline => pipeline,
            :valid    => valid,
            :headline => headline,
            :detail   => detail
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is There a Solid Anywhere Below This Instance?
    # ------------------------------------------------------------
    def self.Na__Subtract__AnySolidBelow?(instance, children = nil)
        budget   = [NA_SUBTRACT_PROBE_NODES]
        children = Na__InsertPrimatives.Na__Subtract__ChildInstances(instance) if children.nil?

        Na__InsertPrimatives.Na__Subtract__ProbeLevel(children, 1, budget)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Level of the Early-Exit Solid Probe
    # ------------------------------------------------------------
    def self.Na__Subtract__ProbeLevel(instances, depth, budget)
        return false if depth > NA_SUBTRACT_MAX_DEPTH

        instances.each do |child|
            return false if budget[0] <= 0
            budget[0] -= 1

            return true if Na__InsertPrimatives.Na__Subtract__Solid?(child)

            grandchildren = Na__InsertPrimatives.Na__Subtract__ChildInstances(child)
            next if grandchildren.empty?

            return true if Na__InsertPrimatives.Na__Subtract__ProbeLevel(grandchildren, depth + 1, budget)
        end

        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Survey Held for an Instance, While It Is Still True
    # ------------------------------------------------------------
    # Keyed on the instance AND on how much is inside it, so a survey taken
    # before an undo, a push or an explode is thrown away rather than shown.
    # ------------------------------------------------------------
    def self.Na__Subtract__SurveyFingerprint(instance)
        definition = instance.respond_to?(:definition) ? instance.definition : nil
        return [instance.entityID, 0, 0] unless definition

        [instance.entityID, definition.entityID, definition.entities.size]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Read the Survey Cache
    # ------------------------------------------------------------
    def self.Na__Subtract__CachedSurvey(instance)
        @na_subtract_survey_cache ||= {}
        held = @na_subtract_survey_cache[instance.entityID]
        return nil unless held

        fingerprint = Na__InsertPrimatives.Na__Subtract__SurveyFingerprint(instance)
        return nil unless fingerprint && fingerprint == held[0]

        held[1]
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Write the Survey Cache and Hand the Survey Straight Back
    # ------------------------------------------------------------
    def self.Na__Subtract__StoreSurvey(instance, survey)
        @na_subtract_survey_cache ||= {}
        fingerprint = Na__InsertPrimatives.Na__Subtract__SurveyFingerprint(instance)
        @na_subtract_survey_cache[instance.entityID] = [fingerprint, survey] if fingerprint
        survey
    rescue StandardError
        survey
    end
    # ---------------------------------------------------------------

    # FUNCTION | Drop Every Held Survey
    # Called after a cut, because the shapes it described are gone.
    # ------------------------------------------------------------
    def self.Na__Subtract__ForgetSurveys
        @na_subtract_survey_cache = {}
        true
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Victim Collection
    # -----------------------------------------------------------------------------

    # FUNCTION | Every Solid Inside the Target the Cutter Can Actually Reach
    # ------------------------------------------------------------
    # Each entry carries the collection the solid lives in as an ABSOLUTE
    # instance path, which is what the commit opens, and the solid's own world
    # transform, which is what the bounding-box gate is measured in.
    #
    # Returns the whole scan state, not just the list, because what the walk
    # SAW is as important as what it chose: 5.1.4 cut one solid out of a nested
    # assembly and the report could not say whether the rest were never found
    # or found and rejected. Every branch of this scan is now counted.
    #
    # DEEPEST FIRST. A solid ancestor and a solid descendant can both be
    # victims, and subtract REPLACES the container it cuts — so a parent cut
    # before its children would strand the references to them. Sorting by
    # context depth removes the ordering question entirely.
    # ------------------------------------------------------------
    def self.Na__Subtract__CollectVictims(target, cutter_box)
        state = {
            :nodes    => 0,                                                   # <-- Instances walked
            :solids   => 0,                                                   # <-- Of those, solids
            :outside  => 0,                                                   # <-- Solids the cutter does not reach
            :skipped  => 0,                                                   # <-- Solids that are locked
            :deepest  => 0,
            :victims  => [],
            :fallback => false
        }

        return state unless target && target[:instance] && target[:instance].valid?

        instance = target[:instance]

        Na__InsertPrimatives.Na__Subtract__WalkChildren(
            instance, target[:transformation], target[:path], 1, state, cutter_box
        )

        # The parent is the FALLBACK, not a competitor. It is cut only when
        # nothing inside it was a solid — the "loose geometry in one watertight
        # shell" case. It deliberately stays a fallback even now that the walk
        # descends through solids: cutting a container AND its contents in one
        # pass means replacing a container whose contents were just rebuilt,
        # and subtract gives no promise about what survives inside it.
        if state[:victims].empty? && Na__InsertPrimatives.Na__Subtract__Solid?(instance)
            state[:fallback] = true
            state[:solids]  += 1
            Na__InsertPrimatives.Na__Subtract__ConsiderVictim(
                instance, target[:transformation], target[:context], state, cutter_box
            )
        end

        state[:victims].sort_by! { |victim| -victim[:context].length }
        state
    rescue StandardError
        state
    end
    # ---------------------------------------------------------------

    # FUNCTION | Walk One Level Down, Collecting Every Solid at Every Depth
    # ------------------------------------------------------------
    # `path` is the ABSOLUTE path of `instance` itself, which is therefore the
    # absolute path of the collection its children live in — so a child's
    # context is its parent's path, with no extra bookkeeping.
    #
    # A SOLID IS STILL DESCENDED INTO. 5.1.4 stopped at the first solid on a
    # branch, reasoning that SketchUp calls nothing a solid if it holds nested
    # instances, so a solid is always a leaf. That reasoning may hold for
    # SketchUp's own UI test, but #manifold? is a different test and the brief
    # is not ambiguous: children AND grandchildren, cut them all. Descending
    # through a solid costs one extra level of iteration and removes an
    # assumption about the API that cannot be checked from here.
    # ------------------------------------------------------------
    def self.Na__Subtract__WalkChildren(instance, world, path, depth, state, cutter_box)
        return if depth > NA_SUBTRACT_MAX_DEPTH
        return if state[:nodes] >= NA_SUBTRACT_MAX_NODES

        state[:deepest] = depth if depth > state[:deepest]

        Na__InsertPrimatives.Na__Subtract__ChildInstances(instance).each do |child|
            break if state[:nodes] >= NA_SUBTRACT_MAX_NODES
            state[:nodes] += 1

            child_world = world * child.transformation

            if Na__InsertPrimatives.Na__Subtract__Solid?(child)
                state[:solids] += 1
                Na__InsertPrimatives.Na__Subtract__ConsiderVictim(child, child_world, path, state, cutter_box)
            end

            Na__InsertPrimatives.Na__Subtract__WalkChildren(
                child, child_world, path + [child], depth + 1, state, cutter_box
            )
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Take a Solid as a Victim Unless Something Rules It Out
    # ------------------------------------------------------------
    # THE BOUNDS GATE FAILS OPEN. It is only an optimisation now: a boolean
    # against a solid the box cannot reach returns nil, and since 5.1.4 that is
    # handled safely rather than being indistinguishable from a real failure.
    # So when the bounds cannot be worked out at all, the solid is KEPT and the
    # boolean is allowed to have the last word — a gate that silently drops a
    # cuttable solid is the worse of the two failures by a distance.
    # ------------------------------------------------------------
    def self.Na__Subtract__ConsiderVictim(instance, world, context, state, cutter_box)
        if instance.respond_to?(:locked?) && instance.locked?
            state[:skipped] += 1
            return false
        end

        bounds = Na__InsertPrimatives.Na__DeepPick__InstanceWorldBounds(instance, world)

        if bounds && cutter_box && !Na__InsertPrimatives.Na__DeepPick__BoxesOverlap?(bounds, cutter_box)
            state[:outside] += 1
            return false
        end

        state[:victims] << {
            :instance     => instance,
            :world        => world,
            :context      => context || [],
            :depth        => (context || []).length,
            :shared_count => Na__InsertPrimatives.Na__Subtract__SharedCount(instance),
            :name         => Na__InsertPrimatives.Na__DeepPick__InstanceName(instance)
        }

        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | How Many Instances Share This One's Definition
    # ------------------------------------------------------------
    def self.Na__Subtract__SharedCount(instance)
        return 1 unless instance.respond_to?(:definition) && instance.definition

        count = instance.definition.instances.length
        count < 1 ? 1 : count
    rescue StandardError
        1
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Cutter Geometry
    # -----------------------------------------------------------------------------

    # FUNCTION | The Eight World Corners of the Box About to Be Cut
    # ------------------------------------------------------------
    def self.Na__Subtract__CutterCorners(spec)
        near = Na__InsertPrimatives.Na__DrawnGrid__BuildRectPoints(
            spec[:origin], spec[:plane_key], spec[:u_len], spec[:v_len]
        )
        return nil unless near

        far = Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(
            near, spec[:plane_key], spec[:d_len]
        )

        near + far
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | That Box as a World-Axis Bounding Box
    # ------------------------------------------------------------
    def self.Na__Subtract__CutterBounds(spec)
        corners = Na__InsertPrimatives.Na__Subtract__CutterCorners(spec)
        return nil unless corners

        box = Geom::BoundingBox.new
        corners.each { |point| box.add(point) }
        box
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build One Cutter Solid in the Collection That Is Open Now
    # ------------------------------------------------------------
    # One per victim, because subtract consumes the cutter. Points go in as
    # world coordinates without conversion: the caller has asserted that this
    # collection is the OPEN editing context, where global is the space
    # entities.add_* accepts.
    # ------------------------------------------------------------
    def self.Na__Subtract__BuildCutter(entities, spec)
        points = Na__InsertPrimatives.Na__DrawnGrid__BuildRectPoints(
            spec[:origin], spec[:plane_key], spec[:u_len], spec[:v_len]
        )
        return nil unless points

        cutter      = entities.add_group
        cutter.name = NA_SUBTRACT_CUTTER_NAME
        Na__InsertPrimatives.Na__DrawnGeom__PinGroupToWorld(cutter)

        face = Na__InsertPrimatives.Na__DrawnGeom__AddExtrudedBox(
            cutter.entities, points, spec[:plane_key], spec[:d_len]
        )

        unless face && Na__InsertPrimatives.Na__Subtract__Solid?(cutter)
            cutter.erase! if cutter && cutter.valid?
            return nil
        end

        cutter
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Identity Preservation
    # -----------------------------------------------------------------------------

    # FUNCTION | Read Everything That Makes a Container Itself
    # ------------------------------------------------------------
    def self.Na__Subtract__CaptureIdentity(instance)
        {
            :name       => (instance.name.to_s rescue ''),
            :layer      => (instance.layer rescue nil),
            :material   => (instance.material rescue nil),
            :hidden     => (instance.hidden? rescue false),
            :casts      => (instance.casts_shadows? rescue true),
            :receives   => (instance.receives_shadows? rescue true),
            :attributes => Na__InsertPrimatives.Na__Subtract__CaptureAttributes(instance)
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Every Attribute Dictionary on a Container, Flattened
    # ------------------------------------------------------------
    def self.Na__Subtract__CaptureAttributes(instance)
        dictionaries = instance.attribute_dictionaries
        return {} unless dictionaries

        captured = {}

        dictionaries.each do |dictionary|
            pairs = {}
            dictionary.keys.each { |key| pairs[key] = dictionary[key] }
            captured[dictionary.name] = pairs
        end

        captured
    rescue StandardError
        {}
    end
    # ---------------------------------------------------------------

    # FUNCTION | Write That Identity Onto the Container the Boolean Produced
    # ------------------------------------------------------------
    def self.Na__Subtract__RestoreIdentity(container, identity)
        return false unless container && container.valid? && identity

        begin
            container.name = identity[:name] unless identity[:name].to_s.empty?
        rescue StandardError
            nil
        end

        begin
            container.layer            = identity[:layer] if identity[:layer]
            container.material         = identity[:material] if identity[:material]
            container.hidden           = identity[:hidden]
            container.casts_shadows    = identity[:casts]
            container.receives_shadows = identity[:receives]
        rescue StandardError
            nil
        end

        identity[:attributes].each do |dictionary_name, pairs|
            pairs.each do |key, value|
                begin
                    container.set_attribute(dictionary_name, key, value)
                rescue StandardError
                    next
                end
            end
        end

        true
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Cut
    # -----------------------------------------------------------------------------

    # FUNCTION | Cut the Described Box Out of Every Solid in the Picked Target
    # ------------------------------------------------------------
    # spec: { :origin, :plane_key, :u_len, :v_len, :d_len, :target }
    # Returns { :success, :cut, :missed, :skipped, :batches, :shared, :message }.
    # ------------------------------------------------------------
    def self.Na__Subtract__Execute(spec)
        unless Na__InsertPrimatives.Na__Subtract__Available?
            return Na__InsertPrimatives.Na__Subtract__Failure('Solid tools need SketchUp Pro — the box was not cut')
        end

        target = spec[:target]
        return Na__InsertPrimatives.Na__Subtract__Failure('Nothing was picked to cut') unless target

        cutter_box = Na__InsertPrimatives.Na__Subtract__CutterBounds(spec)
        return Na__InsertPrimatives.Na__Subtract__Failure('The box has no volume to cut with') unless cutter_box

        scan = Na__InsertPrimatives.Na__Subtract__CollectVictims(target, cutter_box)

        if scan[:victims].empty?
            return Na__InsertPrimatives.Na__Subtract__Failure(
                Na__InsertPrimatives.Na__Subtract__NothingToCutMessage(target, scan), scan
            )
        end

        Na__InsertPrimatives.Na__Subtract__RunBatches(spec, scan)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Why the Scan Came Back With Nothing to Cut
    # Three different situations that all used to read as one flat refusal.
    # ------------------------------------------------------------
    def self.Na__Subtract__NothingToCutMessage(target, scan)
        if scan[:solids].to_i.zero?
            survey = Na__InsertPrimatives.Na__Subtract__Survey(target)
            return "#{survey[:headline]} — #{scan[:nodes]} nested object#{scan[:nodes] == 1 ? '' : 's'} walked, none watertight"
        end

        if scan[:outside].to_i > 0
            return "The box does not reach any of the #{scan[:solids]} solid#{scan[:solids] == 1 ? '' : 's'} inside that object"
        end

        "All #{scan[:solids]} solid#{scan[:solids] == 1 ? '' : 's'} inside that object are locked"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open Each Collection Once and Cut Every Solid It Holds
    # ------------------------------------------------------------
    def self.Na__Subtract__RunBatches(spec, scan)
        model   = Sketchup.active_model
        victims = scan[:victims]
        batches = {}

        # Ruby hashes keep insertion order and the victims arrive deepest-first,
        # so the batches run deepest-first too: a container is never replaced
        # before the solids inside it have been cut.
        victims.each do |victim|
            key = victim[:context].map { |instance| instance.entityID }
            (batches[key] ||= []) << victim
        end

        tally = {
            :cut     => 0,
            :removed => 0,
            :missed  => 0,
            :skipped => 0,
            :batches => batches.length,
            :shared  => 0,
            :errors  => []
        }

        batches.each_value do |batch|
            context = batch.first[:context]

            result = Na__InsertPrimatives.Na__DeepPick__ExecuteInContext(model, context, NA_SUBTRACT_OPERATION) do |_entered|
                Na__InsertPrimatives.Na__Subtract__CutBatch(model, spec, context, batch, tally)
            end

            tally[:errors] << result[:error] if result[:error]
        end

        Na__InsertPrimatives.Na__Subtract__ForgetSurveys

        {
            :success => (tally[:cut] + tally[:removed]) > 0,
            :cut     => tally[:cut],
            :removed => tally[:removed],
            :missed  => tally[:missed],
            :skipped => tally[:skipped] + scan[:skipped].to_i,
            :batches => tally[:batches],
            :shared  => tally[:shared],
            :scan    => scan,
            :message => Na__InsertPrimatives.Na__Subtract__Message(tally)
        }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Cut Every Solid in One Already-Open Collection
    # ------------------------------------------------------------
    # The context assertion is the whole safety of this routine. Entities added
    # to the OPEN context take world coordinates; entities added to a closed
    # definition take local ones. If the open failed, the world box would land
    # in the wrong place in the model and cut a hole somewhere nobody asked
    # for — so the batch is abandoned and counted instead.
    # ------------------------------------------------------------
    def self.Na__Subtract__CutBatch(model, spec, context, batch, tally)
        wanted = context.empty? ? nil : context

        unless Na__InsertPrimatives.Na__DeepPick__SameContext?(model.active_path, wanted)
            tally[:skipped] += batch.length
            raise "could not open the editing context of #{batch.first[:name]}"
        end

        entities = model.active_entities

        batch.each do |victim|
            Na__InsertPrimatives.Na__Subtract__CutOne(entities, spec, victim, tally)
        end
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build One Cutter, Cut One Solid, and Check What Came Back
    # ------------------------------------------------------------
    def self.Na__Subtract__CutOne(entities, spec, victim, tally)
        instance = victim[:instance]

        # A solid collected during the scan can have been erased since by an
        # earlier cut in this same operation — two instances of one definition,
        # or a container replaced beneath it. Counted rather than ignored, so
        # "cut 3 of 5" never goes unexplained.
        unless instance && instance.valid?
            tally[:missed] += 1
            return false
        end

        cutter = Na__InsertPrimatives.Na__Subtract__BuildCutter(entities, spec)

        unless cutter
            tally[:missed] += 1
            return false
        end

        tally[:shared] += 1 if victim[:shared_count].to_i > 1
        identity = Na__InsertPrimatives.Na__Subtract__CaptureIdentity(instance)
        swallowed = Na__InsertPrimatives.Na__Subtract__Swallows?(spec, victim)

        # THE CUTTER IS THE RECEIVER. See the operand-order note in the header:
        # this reads as "subtract the cutter from the victim", and the other way
        # round computes cutter - victim, which for a window in a wall is empty
        # and erases the wall along with it.
        result = Na__InsertPrimatives.Na__Subtract__Apply(cutter, instance)

        if result && result.valid?
            Na__InsertPrimatives.Na__Subtract__RestoreIdentity(result, identity)
            tally[:cut] += 1
            return true
        end

        # Nothing came back. If the solid is still standing the boolean simply
        # declined — clear the cutter away and count a miss.
        if instance.valid?
            cutter.erase! if cutter && cutter.valid?
            tally[:missed] += 1
            return false
        end

        # The solid is GONE and there is no replacement. That is the right
        # answer only when the cutter genuinely encloses it; anything else is
        # the operand order or the API having moved under us, and the whole
        # operation is abandoned rather than committed.
        if swallowed
            tally[:removed] += 1
            return true
        end

        raise "the boolean removed #{victim[:name]} instead of cutting it — nothing was committed"
    end
    # ---------------------------------------------------------------

    # FUNCTION | Does the Cutter Enclose This Solid Completely?
    # The one case where a boolean that leaves nothing behind is correct, and
    # therefore the one case where a vanished solid is not treated as a fault.
    # Bounding boxes only: an approximation is fine because being wrong here
    # costs a refusal and an undo-safe abort, never geometry.
    # ------------------------------------------------------------
    def self.Na__Subtract__Swallows?(spec, victim)
        cutter_box = Na__InsertPrimatives.Na__Subtract__CutterBounds(spec)
        victim_box = Na__InsertPrimatives.Na__DeepPick__InstanceWorldBounds(victim[:instance], victim[:world])
        return false unless cutter_box && victim_box
        return false if cutter_box.empty? || victim_box.empty?

        Na__InsertPrimatives.Na__Subtract__BoxContains?(cutter_box, victim_box)
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the Inner Box Wholly Inside the Outer One?
    # ------------------------------------------------------------
    def self.Na__Subtract__BoxContains?(outer, inner)
        (0..7).all? { |index| outer.contains?(inner.corner(index)) }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run the Boolean, Answering nil Rather Than Raising
    # subtract returns nil when the two solids do not actually intersect, which
    # the bounding-box gate makes unlikely but cannot rule out — two boxes can
    # share a bounding region and no volume.
    # ------------------------------------------------------------
    def self.Na__Subtract__Apply(cutter, instance)
        cutter.subtract(instance)
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | One Line Describing What the Cut Did
    # ------------------------------------------------------------
    def self.Na__Subtract__Message(tally)
        parts = ["Cut #{tally[:cut]} solid#{tally[:cut] == 1 ? '' : 's'}"]
        parts << "#{tally[:removed]} removed entirely" if tally[:removed] > 0
        parts << "#{tally[:missed]} missed"             if tally[:missed]  > 0
        parts << "#{tally[:skipped]} skipped"           if tally[:skipped] > 0
        parts << "#{tally[:shared]} shared definition#{tally[:shared] == 1 ? '' : 's'} — every copy changed" if tally[:shared] > 0
        parts << tally[:errors].first if tally[:errors].any?

        parts.join(' | ')
    end
    # ---------------------------------------------------------------

    # FUNCTION | A Refusal in the Shape of a Result
    # ------------------------------------------------------------
    def self.Na__Subtract__Failure(message, scan = nil)
        {
            :success => false,
            :cut     => 0,
            :removed => 0,
            :missed  => 0,
            :skipped => scan ? scan[:skipped].to_i : 0,
            :batches => 0,
            :shared  => 0,
            :scan    => scan,
            :message => message
        }
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN SUBTRACT MODULE
# =============================================================================
