# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP PUSH PULL PICK SET
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnPushPull__PickSet__.rb
# NAMESPACE  : Na__NobleDrawingTools::DrawnPushPullPickSet
# AUTHOR     : Noble Architecture
# PURPOSE    : Pick several faces at any nesting depth before pushing them
# CREATED    : 2026 (5.2.30)
#
# WHAT IT DOES:
# - Before a face is grabbed, CTRL+click adds the face under the cursor to a
#   pick set, or takes it out again, at any depth: a face in a closed group
#   and a loose face beside it can be picked together, which the Select tool
#   cannot do. CTRL+SHIFT+click adds the face AND its shortest quad ring (Noble
#   3D Tools' Select Shortest Face Ring, run on the face clicked).
# - Then a plain press-drag (or click-move-click) pushes the whole set, each
#   face along its own normal, exactly as a preselection pushes: the set IS a
#   preselection, held in the tool instead of in model.selection, so the
#   preview, joint surfaces, quads, loop cuts, the typed distance and the
#   commit are DrawnPushPullPreselect's.
# - CTRL+SHIFT+DOUBLE-click (5.2.33) picks the ring and pushes the set by the
#   last distance placed at once, as a plain double-click repeats it on one
#   face (na_pk__double_click).
# - BKSP or ESC lets the set go before ESC would leave the tool.
# - The 2D tool (5.2.32) picks the wall behind an edge instead, lets only an
#   edge-on face drive the drag, and the camera handover carries the set
#   across (na_pk__carry, na_pk__incoming=, na_pk__receive).
#
# WHY CTRL+SHIFT AND NOT CTRL+ALT+SHIFT (asked for, 06-Nov-2026):
# - SketchUp 2027 reads Shift+Ctrl+Alt with the mouse as its own pan, and
#   Ctrl+Alt as its touchpad orbit (see Camera__AltGrFilter__), so a hover
#   with the three keys down moves the camera. And the mouse flags never
#   carry ALT, which made every ALT modifier in this plugin brittle (0.4.34,
#   5.1.21, 5.1.23). CTRL and SHIFT are in the flags of every mouse event.
#   ALT held as well changes nothing: the ring is still taken.
#
# FACES IN DIFFERENT GROUPS:
# - A push must run inside the face's own editing context, or the instance's
#   display goes stale (the saga in DrawnPushPullCommit). One operation cannot
#   span two contexts (active_path= refuses inside an open transaction), so a
#   set spread over several groups is pushed one context at a time: the
#   user's own context first, then a hop straight into each of the others,
#   then back. Every operation after a hop is started transparent and every
#   one before a hop next_transparent, so the hops are pulled into the chain
#   and the whole push is meant to undo as one Ctrl+Z. UNMEASURED: check the
#   Ctrl+Z count in SketchUp.
# - It retypes like any push (5.2.34): type 1200 after placing and the whole
#   set becomes 1200, the ghost replaying the change. Because the undo count
#   is unmeasured, the retype does not trust a count: it undoes one step at a
#   time and stops the moment every picked face is back where it started,
#   read in whatever space the context SketchUp left open reports. It never
#   goes past the steps the chain itself could have made, and if the faces
#   are not all back by then it puts everything back with Redo and refuses.
# - Coordinates follow the Coordinate Rule: every recipe (offset, the
#   pushpull scalar, the slope split) is read before the first hop, in the
#   user's own context, and the split is handed to the commit so it is not
#   read again from a face that now reports world.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnDeepPick__'
require_relative '../05__PreviewGraphics/Na__NobleDrawingTools__DrawnPreviewGraphics__'

module Na__NobleDrawingTools

    # -----------------------------------------------------------------------------
    # REGION | Shortest Face Ring (Noble 3D Tools' Select Shortest Face Ring)
    # -----------------------------------------------------------------------------

    NA_PK_RING_MAX_STEPS = 10_000

    # FUNCTION | A Quad's Four Edges in Loop Order, or nil
    # ------------------------------------------------------------
    def self.Na__PushPullPick__QuadEdges(face)
        edges = face.outer_loop.edges
        edges.length == 4 ? edges : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Walk a Ring Out of the Seed Across One Edge
    # ------------------------------------------------------------
    # Across the edge to the one face on its far side, then across that
    # quad's opposite edge, until the ring closes, meets a face that is not a
    # quad, or meets an edge with more or fewer than two faces.
    # ------------------------------------------------------------
    def self.Na__PushPullPick__WalkRing(seed, start_edge)
        collected = []
        seen      = { seed => true }
        face      = seed
        edge      = start_edge

        NA_PK_RING_MAX_STEPS.times do
            others = edge.faces.reject { |candidate| candidate == face }
            break unless others.length == 1

            following = others.first
            break if seen[following]

            edges = Na__NobleDrawingTools.Na__PushPullPick__QuadEdges(following)
            break unless edges

            index = edges.index(edge)
            break unless index

            collected << following
            seen[following] = true
            face = following
            edge = edges[(index + 2) % 4]
        end

        collected
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Seed's Ring Across Its Shorter Pair of Opposite Edges
    # ------------------------------------------------------------
    # Lengths are measured in world (xform takes the face's reported space to
    # world), so a scaled group picks the ring that LOOKS shortest. Ties go to
    # the longer ring, as Noble 3D Tools' strategy does. A face that is not a
    # quad has no ring and comes back alone.
    # ------------------------------------------------------------
    def self.Na__PushPullPick__ShortestRing(seed, xform)
        edges = Na__NobleDrawingTools.Na__PushPullPick__QuadEdges(seed)
        return [seed] unless edges

        xform ||= Geom::Transformation.new
        length = lambda do |edge|
            (edge.start.position.transform(xform) - edge.end.position.transform(xform)).length.to_f
        end

        rings = [[edges[0], edges[2]], [edges[1], edges[3]]].map do |pair|
            faces = [seed] +
                    Na__NobleDrawingTools.Na__PushPullPick__WalkRing(seed, pair[0]) +
                    Na__NobleDrawingTools.Na__PushPullPick__WalkRing(seed, pair[1])
            { :faces => faces.uniq, :length => (length.call(pair[0]) + length.call(pair[1])) / 2.0 }
        end

        rings.min_by { |ring| [ring[:length], -ring[:faces].length] }[:faces]
    rescue StandardError
        [seed]
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Tool Side
    # -----------------------------------------------------------------------------

    module DrawnPushPullPickSet

        # Green offers one face, which turns the set's blue once picked.
        # Yellow is kept for a ring offer only, so a ring always reads as one.
        NA_PK_ADD_FILL      = Sketchup::Color.new( 40, 190,  70,  80)
        NA_PK_ADD_BORDER    = Sketchup::Color.new( 20, 150,  50, 240)
        NA_PK_RING_FILL     = Sketchup::Color.new(255, 200,   0,  70)
        NA_PK_RING_BORDER   = Sketchup::Color.new(230, 160,   0, 240)
        NA_PK_REMOVE_BORDER = Sketchup::Color.new(220,  40,  40, 240)

        # -----------------------------------------------------------------------------
        # REGION | Life Cycle
        # -----------------------------------------------------------------------------

        # ACTIVATE | No Set Yet; the Preselection Is Read Below This
        # ------------------------------------------------------------
        def activate
            @na_pk_picked  = false
            @na_pk_hover   = nil
            @na_pk_refusal = nil
            super
            na_pk__receive
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Set, Handed On When the Camera Swaps the Tool
        # ------------------------------------------------------------
        # Switching to a 2D scene tab replaces this tool with the 2D one (and
        # back), and a set picked in one view is meant to be pushed in the
        # other. Nil when nothing is picked.
        # ------------------------------------------------------------
        def na_pk__carry
            return nil unless na_pk__picked?

            kept = (@na_pps_targets || []).select { |target| target[:face] && target[:face].valid? }
            kept.empty? ? nil : kept
        end
        # ---------------------------------------------------------------

        # FUNCTION | Set Before Activation; Taken Up as the Tool Starts
        # ------------------------------------------------------------
        def na_pk__incoming=(targets)
            @na_pk_incoming = targets
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Up a Set Handed On by the Tool This One Replaced
        # ------------------------------------------------------------
        def na_pk__receive
            incoming        = @na_pk_incoming
            @na_pk_incoming = nil
            return false unless incoming && !incoming.empty?

            @na_pps_targets = incoming.select { |target| target[:face] && target[:face].valid? }
            return false if @na_pps_targets.empty?

            @na_pk_picked = true
            @na_pps_cache = {}
            na_pps__regroup
            @na_last_status_text = nil
            true
        end
        # ---------------------------------------------------------------

        # ON CANCEL | ESC Lets a Pick Set Go Before It Leaves the Tool
        # ------------------------------------------------------------
        def onCancel(reason, view)
            if reason == 0 && @na_state == :idle && na_pk__clear
                na_drawn__update_status_text
                na_drawn__refresh_vcb
                view.invalidate if view
                return
            end

            super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | State
        # -----------------------------------------------------------------------------

        # FUNCTION | Both Tools: the 3D One and the 2D One for a Parallel Camera
        # ------------------------------------------------------------
        def na_pk__supported?
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Face a CTRL Click Here Is About
        # ------------------------------------------------------------
        # The face under the cursor. The 2D tool picks the wall behind an
        # edge instead, which is what its ordinary click grabs.
        # ------------------------------------------------------------
        def na_pk__pick_target(view, x, y, _ring)
            Na__NobleDrawingTools.Na__DeepPick__FaceAt(view, x, y)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Outline Width of a Face on Offer
        # ------------------------------------------------------------
        def na_pk__line_width
            3
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Set Being Pushed One Picked in the Tool?
        # ------------------------------------------------------------
        def na_pk__picked?
            @na_pk_picked ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is CTRL Down With Nothing in Hand?
        # ------------------------------------------------------------
        def na_pk__gesture?
            na_pk__supported? && @na_state == :idle && @na_ctrl_held ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | And SHIFT With It: the Ring
        # ------------------------------------------------------------
        def na_pk__ring_gesture?
            na_pk__gesture? && @na_shift_held ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a CTRL Click on Offer Under the Cursor?
        # ------------------------------------------------------------
        def na_pk__hovering?
            !@na_pk_hover.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Let the Set Go; true When There Was One
        # ------------------------------------------------------------
        # Quiet after a push, which says what it did itself.
        # ------------------------------------------------------------
        def na_pk__clear(quiet = false)
            return false unless na_pk__picked?

            @na_pk_picked   = false
            @na_pk_hover    = nil
            @na_pps_targets = []
            @na_pps_units   = []
            @na_pps_cache   = {}

            unless quiet
                Sketchup::set_status_text('Picked faces let go', SB_PROMPT)
                @na_last_status_text = nil
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Pick in the Set Already?
        # ------------------------------------------------------------
        # The same face in the same copy (5.2.44). Until 5.2.44 a face was ONE
        # pick however many copies of a component it was reached through,
        # because pushing it once per copy pushed every copy that many times.
        # Now copies picked alike are pushed once, through one of them, and
        # copies not picked keep their shape (DrawnDeepUnique, in
        # na_pk__settle): CTRL+clicking the top of three balusters picks three
        # balusters, instead of the second click taking the first back out.
        # ------------------------------------------------------------
        def na_pk__member?(target)
            (@na_pps_targets || []).any? { |member| na_pk__same_pick?(member, target) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Are Two Picks the Same Face in the Same Copy?
        # ------------------------------------------------------------
        def na_pk__same_pick?(one, other)
            one[:face] == other[:face] && na_pps__context_key(one) == na_pps__context_key(other)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Hover and Click
        # -----------------------------------------------------------------------------

        # FUNCTION | What a CTRL Click Here Would Add or Take Out
        # ------------------------------------------------------------
        def na_pk__track(view, x, y)
            @na_pk_hover   = nil
            @na_pk_refusal = nil
            return nil unless na_pk__gesture? && x && y

            ring   = na_pk__ring_gesture?
            target = na_pk__pick_target(view, x, y, ring)
            return nil unless target && target[:face] && !target[:locked]

            faces   = ring ? Na__NobleDrawingTools.Na__PushPullPick__ShortestRing(target[:face], target[:transformation]) : [target[:face]]
            targets = faces.map do |face|
                face == target[:face] ? target : Na__NobleDrawingTools.Na__DeepPick__BuildTarget(face, target[:path], target[:transformation])
            end

            @na_pk_hover = {
                :seed    => target,
                :targets => targets,
                :ring    => ring,
                :quad    => !Na__NobleDrawingTools.Na__PushPullPick__QuadEdges(target[:face]).nil?,
                :remove  => !ring && na_pk__member?(target),
                :fresh   => targets.count { |candidate| !na_pk__member?(candidate) }
            }
        rescue StandardError
            @na_pk_hover = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | A CTRL Click: Pick the Face, or the Ring; true When It Was Ours
        # ------------------------------------------------------------
        # Asked fresh at the click rather than trusting the last hover. A
        # preselection already in the tool becomes the start of the set.
        # ------------------------------------------------------------
        def na_pk__try_click(view, x, y)
            return false unless na_pk__gesture?

            @na_drag_press_active = false
            na_pk__track(view, x, y)
            hover = @na_pk_hover

            unless hover
                UI.beep
                Sketchup::set_status_text(@na_pk_refusal || 'No face under the cursor to pick', SB_PROMPT)
                @na_last_status_text = nil
                return true
            end

            unless na_pk__picked?
                @na_pps_targets = (@na_pps_targets || []).dup
                @na_pk_picked   = true
            end

            if hover[:remove]
                @na_pps_targets = @na_pps_targets.reject { |target| na_pk__same_pick?(target, hover[:seed]) }
            else
                hover[:targets].each { |target| @na_pps_targets << target unless na_pk__member?(target) }
            end

            @na_pps_cache = {}
            na_pps__regroup
            na_revise__forget                                                 # <-- Picking is the "something else" that closes the last push's box
            na_drawn__trace("pick set: #{@na_pps_targets.length} face(s)")

            if @na_pps_targets.empty?
                @na_pk_picked = false
                @na_pk_hover  = nil
            else
                na_pk__track(view, x, y)                                      # <-- The hover now reads "take out" over what was just added
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | CTRL+SHIFT+Double-Click: the Ring, Pushed by the Last Distance
        # ------------------------------------------------------------
        # Native Push/Pull's double-click, on a whole ring. A double click
        # arrives as Down, Up, DoubleClick, Up, and the Down was a CTRL+SHIFT
        # click, which has already put the ring in the set (a ring click only
        # ever adds). So the set is taken up here exactly as a plain click
        # takes it, and pushed by the remembered distance, every face along
        # its own normal. Faces picked before the ring go with it, as they
        # would with a drag. The keys are let go for the push itself: held
        # SHIFT would send every ring face up its slope, and CTRL snaps.
        # Too soon after a placement, or with nothing remembered, the ring
        # stays picked and a drag pushes it as usual.
        # ------------------------------------------------------------
        def na_pk__double_click(view, x, y)
            return true unless na_pk__picked?                                 # <-- The first click found no face, and said so

            unless na_revise__memory?
                na_revise__repeat_or_refuse(view)                             # <-- Beeps: nothing to repeat yet
                @na_last_status_text = nil
                return true
            end
            return true unless na_revise__repeat_allowed?

            held = [@na_ctrl_held, @na_shift_held, @na_alt_held]
            @na_ctrl_held = @na_shift_held = @na_alt_held = false
            @na_pk_hover     = nil
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            begin
                if na_drawn__grab_face(view, x, y)
                    @na_drag_press_active = false
                    na_drawn__trace('CTRL+SHIFT double-click — the picked set repeats the remembered distance')
                    na_revise__apply_repeat(@na_revise_memory, view)
                    na_pk__clear(true) if @na_state == :idle                  # <-- A set of one is let go like a set of many
                end
            ensure
                @na_ctrl_held, @na_shift_held, @na_alt_held = held
            end

            na_drawn__update_cursor(view, x, y) if @na_state == :idle
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw What a CTRL Click Would Do
        # ------------------------------------------------------------
        def na_pk__draw(view)
            hover = @na_pk_hover
            return unless hover

            fill   = hover[:ring] ? NA_PK_RING_FILL : NA_PK_ADD_FILL
            border = if    hover[:remove] then NA_PK_REMOVE_BORDER
                     elsif hover[:ring]   then NA_PK_RING_BORDER
                     else                      NA_PK_ADD_BORDER
                     end
            first  = nil

            hover[:targets].each do |target|
                face = target[:face]
                next unless face && face.valid?

                xform = target[:transformation]
                loop  = Na__NobleDrawingTools.Na__DeepPick__WorldOuterLoop(face, xform)
                first ||= loop.first
                Na__NobleDrawingTools.Na__DrawnPreview__DrawTriangles(view, Na__NobleDrawingTools.Na__DeepPick__WorldTriangles(face, xform), fill) unless hover[:remove]
                Na__NobleDrawingTools.Na__DrawnPreview__DrawLoop(view, loop, border, na_pk__line_width)
            end

            return unless first

            Na__NobleDrawingTools.Na__DrawnPreview__DrawWorldLabel(view, first, na_pk__label_lines(hover))
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Words Beside the Candidate
        # ------------------------------------------------------------
        def na_pk__label_lines(hover)
            lines = []

            if hover[:remove]
                lines << 'CTRL+click takes this face out'
            elsif hover[:ring]
                lines << (hover[:quad] ? "Shortest ring: #{hover[:targets].length} face#{hover[:targets].length == 1 ? '' : 's'}" : 'Not a quad — no ring, the face alone')
                lines << "CTRL+SHIFT+click adds #{hover[:fresh]}"
                lines << "CTRL+SHIFT+double-click repeats #{na_revise__value_label(@na_revise_memory)}" if na_revise__memory?
            else
                lines << 'CTRL+click adds this face'
            end

            lines << Na__NobleDrawingTools.Na__DeepPick__PathLabel(hover[:seed])
            lines
        end
        # ---------------------------------------------------------------

        # FUNCTION | Points the Candidate Occupies, for the Draw Extents
        # ------------------------------------------------------------
        def na_pk__preview_points
            return [] unless @na_pk_hover

            @na_pk_hover[:targets].flat_map do |target|
                face = target[:face]
                face && face.valid? ? Na__NobleDrawingTools.Na__DeepPick__WorldOuterLoop(face, target[:transformation]) : []
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Line
        # -----------------------------------------------------------------------------

        # FUNCTION | The Middle of the Status Line While CTRL Is Down
        # ------------------------------------------------------------
        def na_pk__status
            count = (@na_pps_targets || []).length
            held  = na_pk__picked? ? " (#{count} picked)" : ''
            hover = @na_pk_hover

            return "#{@na_pk_refusal}#{held}" if !hover && @na_pk_refusal
            return "CTRL: click faces at any depth to pick them, CTRL+SHIFT the shortest ring#{held}" unless hover
            return "CTRL+click takes this face out#{held}" if hover[:remove]
            return "CTRL+SHIFT+click adds the shortest ring, #{hover[:fresh]} new of #{hover[:targets].length}#{held}#{na_pk__repeat_hint}" if hover[:ring] && hover[:quad]
            return "Not a quad, so no ring — CTRL+SHIFT+click adds the face alone#{held}#{na_pk__repeat_hint}" if hover[:ring]

            "CTRL+click adds this face#{held}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a CTRL+SHIFT Double-Click Would Repeat, or ''
        # ------------------------------------------------------------
        def na_pk__repeat_hint
            na_revise__memory? ? " — dbl-click to repeat #{na_revise__value_label(@na_revise_memory)}" : ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Keys, Named at the End of the Status Line
        # ------------------------------------------------------------
        def na_pk__key_hint
            return '' unless na_pk__supported? && @na_state == :idle

            na_pk__picked? ? '  CTRL+click pick  CTRL+SHIFT ring  BKSP drops picks' : '  CTRL+click pick faces  CTRL+SHIFT+click ring'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Pushing a Set That Spans Several Contexts
        # -----------------------------------------------------------------------------

        # FUNCTION | Does Any Recipe Live Outside the User's Own Context?
        # ------------------------------------------------------------
        def na_pk__spans_contexts?(recipes, home)
            recipes.any? { |recipe| !Na__NobleDrawingTools.Na__DeepPick__SameContext?(home, recipe[:context]) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Recipes Grouped Into Stages, the User's Own Context First
        # ------------------------------------------------------------
        def na_pk__stages(recipes, home)
            stages = []

            recipes.each do |recipe|
                stage = stages.find { |candidate| Na__NobleDrawingTools.Na__DeepPick__SameContext?(candidate[:context], recipe[:context]) }
                stage ||= (stages << { :context => recipe[:context], :recipes => [] }).last
                stage[:recipes] << recipe
            end

            home_first = stages.partition { |stage| Na__NobleDrawingTools.Na__DeepPick__SameContext?(home, stage[:context]) }
            home_first.flatten(1)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push Every Stage in Its Own Context, Chained as One Undo
        # ------------------------------------------------------------
        # Raises on the first failure, with the stage's operation aborted and
        # the user put back where they were. Stages already pushed stay pushed
        # (they are committed operations) and the message says how many.
        # Returns { :done, :records, :stages }: a retype record per recipe,
        # nil for one that could not be recorded.
        # ------------------------------------------------------------
        def na_pk__apply_chain(model, recipes, distance, home)
            settle   = na_pk__settle(model, recipes)                          # <-- 5.2.44: copies of a component picked alike pushed once, the rest kept
            recipes  = settle[:recipes]
            stages   = na_pk__stages(recipes, home)
            current  = model.active_path                                      # <-- home, or the container the settle left open
            opened   = false
            done     = 0
            records  = []
            selected = settle[:pending] ? settle[:selected] : Na__NobleDrawingTools.Na__DeepPick__FocusSnapshot(model)

            begin
                stages.each_with_index do |stage, index|
                    hopped = false

                    unless Na__NobleDrawingTools.Na__DeepPick__SameContext?(current, stage[:context])
                        model.active_path = stage[:context]                   # <-- Outside any operation: active_path= refuses inside one
                        current = stage[:context]
                        hopped  = true
                        na_drawn__trace("pick set: entered #{stage[:context] ? stage[:context].length : 0} deep")
                    end

                    last        = index == stages.length - 1
                    more_follow = !last || !Na__NobleDrawingTools.Na__DeepPick__SameContext?(current, home)
                    transparent = index > 0 || hopped || settle[:pending]     # <-- Never merged into what the user did before the push; always into the settle
                    model.start_operation('Deep Push Pull (Picked Faces)', true, more_follow, transparent)
                    opened = true

                    @na_pps_transaction = true
                    @na_pk_chain        = { :entered => !Na__NobleDrawingTools.Na__DeepPick__SameContext?(home, stage[:context]) }

                    stage[:recipes].each do |recipe|
                        records << na_pk__apply_recipe(model, recipe, distance)
                        done += 1
                    end

                    model.commit_operation
                    opened = false
                end
            rescue StandardError => error
                model.abort_operation if opened
                opened = false
                message = done.zero? ? error.message : "#{error.message} (#{done} of #{recipes.length} already pushed — Ctrl+Z takes them back)"
                raise message
            ensure
                @na_pk_chain = nil
                unless Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, home)
                    na_drawn__restore_context(model, home)
                    Na__NobleDrawingTools.Na__DeepPick__FocusRestore(model, selected)
                end
            end

            { :done => done, :records => records, :stages => stages.length, :riders => settle[:riders] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Settle the Copies the Picked Faces Sit In (5.2.44)
        # ------------------------------------------------------------
        # Every recipe was read in the user's own context, so its offset is
        # the push as its face's own definition reads it: the same face in
        # copies of one component, pushed the same way, signs the same and is
        # pushed ONCE (DrawnDeepUnique), the copies riding along; copies not
        # picked keep their shape. A surface (joint) recipe signs as its copy
        # alone. Hands back the recipes still to push, each in the copy it now
        # sits in (its context and face moved across; its anchor, split and
        # snapshot are world or local readings that still hold), plus what
        # the chain needs to finish the step. Raises when nothing may change.
        # ------------------------------------------------------------
        def na_pk__settle(model, recipes)
            targets = recipes.map { |recipe| recipe[:kind] == :joint ? recipe[:unit][:targets].first : recipe[:data][0] }
            offsets = {}
            recipes.each_with_index { |recipe, index| offsets[targets[index].object_id] = recipe[:data][2] unless recipe[:kind] == :joint }

            sign = lambda do |target|
                offset = offsets[target.object_id]
                offset ? [:face, target[:face].entityID, Na__NobleDrawingTools.Na__DeepUnique__Quantise(offset)] : nil
            end

            settle = Na__NobleDrawingTools.Na__DeepUnique__SettleTargets(model, targets, 'Deep Push Pull (Picked Faces)', sign)
            raise settle[:refused] if settle[:refused]

            live = []
            recipes.each_with_index do |recipe, index|
                moved = settle[:targets][index]
                next unless moved                                             # <-- Rides on a copy's push: the same face, the same way, already in the set

                instances = Na__NobleDrawingTools.Na__DeepPick__Instances(moved[:path])
                context   = instances.empty? ? nil : instances

                if recipe[:kind] == :joint
                    live << recipe.merge(:context => context)                 # <-- Its faces are found again by their anchors once open
                else
                    data    = recipe[:data].dup
                    data[0] = moved
                    live << recipe.merge(:context => context, :data => data)
                end
            end

            settle.merge(:recipes => live)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push One Recipe Inside the Stage's Open Operation
        # ------------------------------------------------------------
        # Returns the recipe's retype record. Everything it is made of was
        # read in the user's own context before the first hop (the snapshot,
        # the offset, the ghost); only the collection is asked of the face
        # now, because opening its group may have made the group unique.
        # ------------------------------------------------------------
        def na_pk__apply_recipe(model, recipe, distance)
            entered = @na_pk_chain[:entered]

            if recipe[:kind] == :joint
                faces = entered ? na_jp__faces_in_open(model, recipe[:plan], recipe[:anchors]) : recipe[:plan][:faces]
                raise 'A picked surface could not be found again inside its group' unless faces && faces.none?(&:nil?) && faces.all?(&:valid?)

                return na_jp__apply_in_batch(model, recipe.merge(:faces => faces), distance)
            end

            target, snapshot, offset, sloped, cutting, ghost = recipe[:data]
            target = na_pk__refind(model, target, recipe[:anchor]) if entered
            raise 'A picked face could not be found again inside its group' unless target && target[:face].valid?

            record = nil

            na_pk__wearing(recipe[:state], target) do
                @na_pk_chain[:split] = recipe[:split]
                raise(@na_pp_last_error || 'Push failed') unless na_drawn__execute_push(model, target, offset)

                if cutting && (@na_pp_quad_stats.nil? || @na_pp_quad_stats[:kept].to_i.zero?)
                    raise 'A picked face could not produce a loop cut'
                end

                na_revise__capture(target, snapshot, offset, sloped, cutting)
                record = @na_revise_record ? @na_revise_record.merge(:ghost => ghost) : nil
            end

            record
        ensure
            @na_pk_chain[:split] = nil if @na_pk_chain
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Face Again, Once Its Group Is Open
        # ------------------------------------------------------------
        # Itself whenever it belongs to the open context. If opening the group
        # made it unique, the face picked a moment ago belongs to the copy left
        # behind, and it is found by the world point inside it (the open
        # context reports world) and its world normal.
        # ------------------------------------------------------------
        def na_pk__refind(model, target, anchor)
            face  = target[:face]
            owner = model.active_entities.parent
            return target if face && face.valid? && face.parent == owner
            return nil unless anchor

            point, normal = anchor
            found = model.active_entities.grep(Sketchup::Face).find do |candidate|
                candidate.valid? && candidate.normal.dot(normal) > 0.999 &&
                    candidate.classify_point(point) == Sketchup::Face::PointInside
            end

            found ? target.merge(:face => found) : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Wear One Face's State, Read Before Any Group Was Opened
        # ------------------------------------------------------------
        # Not na_pps__with_target: that adopts the face afresh, and inside its
        # group the face reports world while the target's transform still
        # takes local to world, so every cached reading would come out wrong.
        # ------------------------------------------------------------
        def na_pk__wearing(state, target)
            names = DrawnPushPullPreselect::NA_PPS_TARGET_STATE
            saved = names.map { |name| instance_variable_get(name) }
            names.zip(state).each { |name, value| instance_variable_set(name, value) } if state
            @na_pp_target = target
            yield
        ensure
            names.zip(saved).each { |name, value| instance_variable_set(name, value) }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Retyping a Set That Spans Several Contexts
        # -----------------------------------------------------------------------------

        # FUNCTION | Arm the Retype for a Set Pushed One Context at a Time
        # ------------------------------------------------------------
        # The same face batch a set in one context arms, plus what the chained
        # undo needs. Not armed when any face could not be recorded: a retype
        # that rebuilt only part of the set would be worse than none.
        # ------------------------------------------------------------
        def na_pk__arm_chain(records, stages)
            return na_revise__forget if records.nil? || records.empty? || records.any?(&:nil?)

            counts = records.map { |member| member[:entities] }.compact.uniq.map do |entities|
                [entities, na_revise__entity_count(entities)]
            end

            na_revise__arm(records.first.merge(
                :kind    => :face_batch,
                :members => records,
                :counts  => counts,
                :picked  => true,
                :ops     => 1,
                :chain   => { :stages => stages, :limit => (2 * stages) + 1 },   # <-- An op per stage, a hop before each, the way home
                :ghost   => { :members => records.map { |member| member[:ghost] } }
            ))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take a Chained Push Back, One Undo Step at a Time
        # ------------------------------------------------------------
        # Overrides the shared count-based undo for a chain record only. The
        # first undo is certainly ours (the watch closes the record the moment
        # anything else lands); each one after it is taken only while some
        # picked face is still where the push left it, so the walk can stop
        # anywhere inside the chain and never reaches past it.
        # ------------------------------------------------------------
        def na_revise__undo_ops(record)
            return super unless record && record[:chain]

            na_pk__undo_chain(record)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Undo Until Every Picked Face Is Back, or Put It All Back
        # ------------------------------------------------------------
        def na_pk__undo_chain(record)
            model  = Sketchup.active_model
            limit  = [record[:chain][:limit].to_i, 1].max
            undone = 0

            while undone < limit
                Sketchup.undo
                undone += 1

                if record[:members].all? { |member| na_pk__member_back?(member, model) }
                    na_drawn__trace("pick set retype: #{undone} undo step(s) took the push back")
                    return true
                end
            end

            undone.times { Sketchup.send_action('editRedo:') }
            Na__NobleDrawingTools.Na__Debug__Puts "NA PICK SET: #{undone} undo step(s) did not bring every picked face back — Redo sent to put them back"
            false
        rescue StandardError => error
            Na__NobleDrawingTools.Na__Debug__Puts "NA PICK SET: chained undo raised — #{error.message}"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Member's Face (or Every Face of Its Surface) Back?
        # ------------------------------------------------------------
        # Back means a face with the same orientation holds the point that was
        # inside it before the push. A pushed face has left that point in every
        # route: out, in, a loop cut, a slope, a stretched surface. The point
        # and normal were read in the user's own context, so they are moved
        # into whatever space the face reports now (na_pk__probe_xform). The
        # normal is only compared by side: M*n is not the true normal under a
        # non-uniform scale, but it always lies on the same side of it.
        # ------------------------------------------------------------
        def na_pk__member_back?(member, model)
            if member[:kind] == :joint
                rows     = member[:faces].map { |row| [row[:interior], row[:normal]] }
                entities = na_jp__live_entities(member)
            else
                rows     = [[member[:interior], member[:normal]]]
                entities = na_revise__live_entities(member[:target][:face], member[:entities])
            end
            return false unless entities && rows.all? { |interior, normal| interior && normal }

            xform = na_pk__probe_xform(member, model)
            faces = entities.grep(Sketchup::Face)

            rows.all? do |interior, normal|
                point     = xform ? interior.transform(xform) : interior
                direction = xform ? normal.transform(xform) : normal

                faces.any? do |face|
                    face.valid? && face.normal.dot(direction) > 0.0 &&
                        face.classify_point(point) == Sketchup::Face::PointInside
                end
            end
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | From the Space the Member Was Read In to the Space It Reports Now
        # ------------------------------------------------------------
        # nil when the two agree. A face reports world while its context is
        # open or holds the open one, local otherwise. The target's transform
        # takes its local space to world (PickHelper's, read in the user's own
        # context, which reports world).
        # ------------------------------------------------------------
        def na_pk__probe_xform(member, model)
            target  = member[:target]
            context = Na__NobleDrawingTools.Na__DeepPick__Instances(target[:path])
            then_w  = na_pk__covers?(member[:user_path], context)
            now_w   = na_pk__covers?(model.active_path, context)
            return nil if then_w == now_w

            xform = target[:transformation] || Geom::Transformation.new
            now_w ? xform : xform.inverse
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does This Open Path Reach Into (or Through) the Context?
        # ------------------------------------------------------------
        def na_pk__covers?(open_path, context)
            open = (open_path || []).to_a
            return false if context.length > open.length

            context.each_with_index.all? { |instance, index| open[index] == instance }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end

    # endregion -------------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
