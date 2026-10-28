# =============================================================================
# NA INSERT PRIMATIVES - DEEP PROJECT TARGETS AND DIRECTIONS
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnProject__Target__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnProjectTarget
# AUTHOR     : Noble Architecture
# PURPOSE    : What the face is carried to (a plane, a point, an object) and
#              which way it travels (normal, slope, follow, an axis, an edge)
# CREATED    : 2026
#
# DESCRIPTION:
# - The second click of Deep Project picks what the face should reach, and
#   the cursor says what that is:
#     a face       its PLANE — every corner lands on it
#     CTRL         a POINT, through SketchUp's own inference — the face stops
#                  level with it (CTRL+SHIFT rounds that height onto the grid)
#     SHIFT+TAB    OBJECT mode: the group or component under the cursor — the
#                  face stops where it first touches it
#     an edge      not a target at all but a DIRECTION: click it, or press
#                  DOWN over it, and the face travels parallel to it
# - The direction is everything else the push tool already taught: the face
#   normal, SHIFT for the neighbour's slope, SHIFT+ALT for every corner along
#   its own edge, the arrow keys for red, green and blue. A locked axis or
#   edge outranks the held keys — it is the more deliberate of the two — and
#   stays locked from one projection to the next until it is released.
#
# DOWN, AND WHY IT IS THE EDGE KEY:
# - In SketchUp's own Move and Line tools the down arrow locks to the edge
#   under the cursor (the magenta parallel lock). Here it does the same, at
#   any nesting depth. Pressed over the locked edge again, or with no edge
#   under the cursor, it FLIPS the direction end for end.
# - A plane is reached whichever way it lies (the geometry header says why),
#   so the flip decides which way an OBJECT is looked for: the one target
#   that has to be found by looking. Left on auto, both ways are tried and
#   the face's own side wins.
#
# ALT, TRACKED BESIDE SHIFT:
# - Exactly as the push tool's FOLLOW does it, for the same reasons: there is
#   no ALT bit in the mouse flags, and a bare ALT belongs to the menu bar.
#   ALT only counts with SHIFT held, and SHIFT going up takes ALT with it.
#
# SHIFT+TAB, AND WHY NOT A LETTER:
# - Drawn Volume's Subtraction switch (5.1.24) set the pattern: TAB is a key
#   the tool already owns, SHIFT is reported on every mouse event, and the
#   pair needs nothing from the menu bar. Plain TAB stays QUADS, as in the
#   push tool. The option is the same one the right-click menu shows, so the
#   two can never disagree.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Focus__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Pick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Instance__'
require_relative '../30__System__DeepPushPull/Na__InsertPrimatives__DrawnPushPull__Follow__'
require_relative 'Na__InsertPrimatives__DrawnProject__Geometry__'

module Na__InsertPrimatives

    module DrawnProjectTarget

        # -----------------------------------------------------------------------------
        # REGION | Constants
        # -----------------------------------------------------------------------------

        NA_PJ_OBJECT_OPTION = 'project_hit_object'.freeze                    # <-- Declared in NA_TOOL_OPTIONS under :drawn_project
        NA_PJ_TAB_KEY       = 9                                               # <-- No VK_TAB constant in the SketchUp API

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | State
        # -----------------------------------------------------------------------------

        # FUNCTION | Create Every Instance Variable This Mixin Relies On
        # ------------------------------------------------------------
        def na_pj__init_target_state
            @na_pj_target      = nil                                          # <-- What the cursor offers in the target stage
            @na_pj_edge_hover  = nil                                          # <-- An edge under the cursor, offered as a direction
            @na_pj_edge_lock   = nil                                          # <-- The edge the face travels parallel to, or nil
            @na_pj_sense       = :auto                                        # <-- Which way an object is looked for: :auto, 1.0, -1.0
            @na_pj_found_sense = 1.0                                          # <-- Which way :auto last found one
            @na_pj_offset      = 0.0                                          # <-- Inches; + stops short, - runs past
            @na_alt_held       = false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is OBJECT Mode On?
        # ------------------------------------------------------------
        def na_pj__object_mode?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_PJ_OBJECT_OPTION)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is SHIFT+ALT Down?
        # ------------------------------------------------------------
        def na_pj__follow_requested?
            @na_shift_held && @na_alt_held ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Direction Mode Is Live
        # ------------------------------------------------------------
        # A locked edge or axis first, because it was set on purpose and stays
        # set; the held keys after it, FOLLOW before SLOPE because SHIFT+ALT
        # includes SHIFT.
        # ------------------------------------------------------------
        def na_pj__mode
            return :edge   if @na_pj_edge_lock
            return :axis   if @na_axis_lock
            return :follow if na_pj__follow_requested?
            return :slope  if @na_shift_held

            :normal
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Sense Actually in Use: Forced, or What :auto Found
        # ------------------------------------------------------------
        def na_pj__sense_value
            @na_pj_sense.is_a?(Numeric) ? @na_pj_sense.to_f : @na_pj_found_sense.to_f
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Tracking the Target
        # -----------------------------------------------------------------------------

        # FUNCTION | Find What the Cursor Is Offering in the Target Stage
        # ------------------------------------------------------------
        # CTRL means a point and nothing else is looked at. Otherwise an edge
        # under the cursor is offered as a direction ahead of the face it
        # borders, the way the Select tool takes the edge when you are on it;
        # away from edges, the face is the target.
        # ------------------------------------------------------------
        def na_pj__track_target(view, x, y)
            @na_pj_edge_hover = nil

            if @na_ctrl_held
                @na_pj_target = na_pj__point_target(view, x, y)
                return @na_pj_target
            end

            edge = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)
            if edge
                @na_pj_edge_hover = na_pj__edge_candidate(edge)
                @na_pj_target     = nil
                return nil
            end

            picked = Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)
            @na_pj_target =
                if picked.nil?             then nil
                elsif na_pj__object_mode?  then na_pj__object_target(picked)
                else                            na_pj__plane_target(picked)
                end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Face's Plane as the Target
        # ------------------------------------------------------------
        # The face being projected is not a target — over it, the cursor is
        # simply still on its way to one — so it answers nil rather than a
        # refusal that would flash red the moment the face is taken.
        # ------------------------------------------------------------
        def na_pj__plane_target(picked)
            face  = picked[:face]
            xform = picked[:transformation]
            return nil unless face && face.valid?
            return nil if na_pj__source_face?(face)

            key = [:plane, face.entityID, face.vertices.first.position.to_a, xform.to_a]
            return @na_pj_target if @na_pj_target && @na_pj_target[:key] == key

            loop = Na__InsertPrimatives.Na__DeepPick__WorldOuterLoop(face, xform)
            return nil if loop.empty?

            {
                :kind      => :plane,
                :key       => key,
                :face      => face,
                :plane     => [loop.first, picked[:world_normal]],
                :triangles => Na__InsertPrimatives.Na__DeepPick__WorldTriangles(face, xform),
                :loop      => loop,
                :name      => "the plane of #{Na__InsertPrimatives.Na__DeepPick__PathLabel(picked)}"
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Inferred Point as the Target
        # ------------------------------------------------------------
        # The shared input point picks from the grabbed point, so SketchUp's
        # own inference — endpoints, midpoints, on-axis from the face — is all
        # there, through any nesting, exactly as the push tool's CTRL has it.
        # ------------------------------------------------------------
        def na_pj__point_target(view, x, y)
            point = na_drawn__input_point_position(view, x, y)
            return nil unless point

            round = (na_drawn__snap_mode == :vertex_grid)
            tip   = @na_ip.respond_to?(:tooltip) ? @na_ip.tooltip.to_s : ''

            {
                :kind  => :point,
                :key   => [:point, point.to_a, round],
                :point => point,
                :round => round,
                :name  => tip.empty? ? 'the point' : "the point (#{tip})"
            }
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Object Under the Cursor as the Target
        # ------------------------------------------------------------
        # Refusals come back as targets carrying a :refusal, not as nil, so the
        # object is still outlined — in red, with the reason across it — and
        # the user can see what was meant and why it will not do.
        # ------------------------------------------------------------
        def na_pj__object_target(picked)
            instance, xform = na_pj__object_for(picked)

            unless instance
                return {
                    :kind    => :object,
                    :key     => [:loose, picked[:face].entityID],
                    :name    => 'loose geometry',
                    :refusal => 'that face belongs to no group or component — SHIFT+TAB aims at its plane instead'
                }
            end

            key = [:object, instance.entityID, xform.to_a]
            return @na_pj_target if @na_pj_target && @na_pj_target[:key] == key

            # Kept until the model changes, so sliding across the object's
            # edges (each one offered as a direction on the way) does not
            # throw away a contact that took a sweep to find. The copy handed
            # out shares the cached :memo, which is where the contacts live.
            cache  = (@na_pj_object_targets ||= {})
            target = cache[key] || na_pj__read_object(instance, xform, key)
            cache.clear if cache.length > 8 && !cache.key?(key)
            cache[key] = target

            if na_pj__holds_source?(instance)
                return target.merge(:refusal => "#{target[:name]} holds the face being projected — pick another object")
            end

            target
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read an Object Once: Its Box, Its Scan, and Why Not
        # ------------------------------------------------------------
        def na_pj__read_object(instance, xform, key)
            name   = Na__InsertPrimatives.Na__DeepPick__InstanceName(instance)
            target = {
                :kind           => :object,
                :key            => key,
                :instance       => instance,
                :transformation => xform,
                :name           => name,
                :quads          => Na__InsertPrimatives.Na__DeepPick__InstanceBoxQuads(instance, xform),
                :memo           => {}
            }

            scan = Na__InsertPrimatives.Na__Project__CachedScan(instance, xform)
            return target.merge(:refusal => "#{name} could not be read") unless scan
            return target.merge(:refusal => "#{name} is too big to sweep against — SHIFT+TAB aims at one of its faces") if scan[:truncated]
            return target.merge(:refusal => "#{name} has nothing in it to touch") if scan[:triangles].empty? && scan[:edges].empty?

            target.merge(:scan => scan)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget Every Object Read — the Model Has Changed
        # ------------------------------------------------------------
        def na_pj__forget_objects
            @na_pj_object_targets = {}
            Na__InsertPrimatives.Na__Project__ForgetScans
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Object a Picked Face Stands For, and Where It Stands
        # ------------------------------------------------------------
        # The innermost group or component holding the face — the one a
        # double-click would open — unless the user has SELECTED one further
        # up the path, which names the object outright: the selection is an
        # instruction, as it is everywhere else in this plugin.
        #
        # THE TRANSFORMATION, BY THE COORDINATE RULE:
        # - The pick's own transformation maps the face's definition to world,
        #   and that definition IS the innermost instance's, so it is that
        #   instance's world placement as it stands.
        # - A selected instance lives in the open context, whose coordinates
        #   are global, so its own #transformation is already its world one.
        # - A face in the open context itself belongs to no closed object at
        #   all: the instances on its path are the groups the user has OPEN.
        # ------------------------------------------------------------
        def na_pj__object_for(picked)
            instances = Na__InsertPrimatives.Na__DeepPick__Instances(picked[:path])
            open      = Na__InsertPrimatives.Na__DeepPick__ContextDepth
            closed    = instances[open..-1] || []
            return [nil, nil] if closed.empty?

            focus = Na__InsertPrimatives.Na__DeepPick__FocusSet
            if focus
                chosen = closed.find { |instance| focus[instance.entityID] }
                return [chosen, chosen.transformation] if chosen
            end

            [closed.last, picked[:transformation]]
        rescue StandardError
            [nil, nil]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This One of the Faces Being Projected?
        # ------------------------------------------------------------
        def na_pj__source_face?(face)
            (@na_pj_sources || []).any? { |source| source[:target][:face] == face }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does This Object Hold One of the Faces Being Projected?
        # A face cannot be stopped by its own solid: every contact would be at
        # no travel at all, and the refusal says so rather than doing nothing.
        # ------------------------------------------------------------
        def na_pj__holds_source?(instance)
            (@na_pj_sources || []).any? do |source|
                (source[:target][:path] || []).include?(instance)
            end
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Edge Directions
        # -----------------------------------------------------------------------------

        # FUNCTION | An Edge Under the Cursor, Offered as a Direction
        # ------------------------------------------------------------
        def na_pj__edge_candidate(picked)
            edge  = picked[:edge]
            xform = picked[:transformation]
            return nil unless edge && edge.valid?

            start  = edge.start.position.transform(xform)
            finish = edge.end.position.transform(xform)
            length = start.distance(finish).to_f
            return nil unless length > 0.0

            direction = finish - start

            {
                :key       => [edge.entityID, xform.to_a],
                :points    => [start, finish],
                :direction => direction.normalize,
                :length    => length,
                :name      => Na__InsertPrimatives.Na__DeepPick__PathLabel(picked),
                :refusal   => na_pj__edge_refusal(direction)
            }
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why an Edge Cannot Carry These Faces, or nil
        # Refused only when it can carry NONE of them: with several faces
        # preselected, the ones it cannot carry say so on their own.
        # ------------------------------------------------------------
        def na_pj__edge_refusal(direction)
            sources = @na_pj_sources || []
            return nil if sources.empty?

            usable = sources.any? { |source| Na__InsertPrimatives.Na__Project__Motion(direction, source[:normal]) }
            usable ? nil : 'runs along the face — it cannot carry it anywhere'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lock the Direction to an Edge, or Flip It If It Is Already Locked
        # ------------------------------------------------------------
        def na_pj__lock_edge(candidate, view)
            return false unless candidate

            if @na_pj_edge_lock && @na_pj_edge_lock[:key] == candidate[:key]
                return na_pj__flip(view)
            end

            if candidate[:refusal]
                UI.beep
                na_revise__notice("That edge #{candidate[:refusal]}")
                return false
            end

            @na_pj_edge_lock = candidate
            @na_axis_lock    = nil                                            # <-- An edge replaces an axis; one direction at a time
            @na_pj_sense     = :auto
            na_pj__after_key(view)
            na_revise__notice("Projecting parallel to the edge in #{candidate[:name]} — DOWN flips it, BKSP releases it")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Turn the Travel End for End
        # ------------------------------------------------------------
        def na_pj__flip(view)
            @na_pj_sense = -na_pj__sense_value
            na_pj__after_key(view)

            word = @na_pj_sense > 0.0 ? 'out from the face' : 'back through the face'
            na_revise__notice("Direction flipped — an object is looked for #{word}; a plane is reached whichever way it lies")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Edge Under the Cursor Right Now, Wherever the Tool Is
        # DOWN can be pressed before a face is taken, so this asks afresh
        # rather than relying on the target stage's hover.
        # ------------------------------------------------------------
        def na_pj__edge_under_cursor(view)
            return @na_pj_edge_hover if @na_pj_edge_hover
            return nil unless view

            picked = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, @na_last_mouse_x, @na_last_mouse_y)
            picked ? na_pj__edge_candidate(picked) : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Direction an Edge Lock Is Drawn Pointing
        # Its own direction turned to the face's outward side, then the sense,
        # so the arrow on the edge always says which way an object is sought.
        # ------------------------------------------------------------
        def na_pj__edge_display_direction
            return nil unless @na_pj_edge_lock

            direction = @na_pj_edge_lock[:direction]
            first     = (@na_pj_sources || []).first
            direction = direction.reverse if first && direction.dot(first[:normal]) < 0.0
            na_pj__sense_value < 0.0 ? direction.reverse : direction
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Keys
        # -----------------------------------------------------------------------------

        # FUNCTION | Arrow Keys: RIGHT / LEFT / UP Lock an Axis, DOWN Takes an Edge
        # ------------------------------------------------------------
        # The shared key handler routes all four arrows here, DOWN with no
        # axis. An axis that every face being projected lies edge-on to is
        # refused with a beep, as the push tool refuses one, rather than
        # leaving a preview that cannot move.
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            return na_pj__down_key(view) if axis.nil?

            previous      = @na_axis_lock
            @na_axis_lock = (@na_axis_lock == axis) ? nil : axis

            if @na_axis_lock && !na_pj__axis_usable?(@na_axis_lock)
                @na_axis_lock = previous
                UI.beep
                Sketchup::set_status_text(
                    "The face is edge-on to #{NA_DRAWN_AXIS_LABELS[axis]} — it cannot travel along it",
                    SB_PROMPT
                )
                return false
            end

            @na_pj_edge_lock = nil if @na_axis_lock                           # <-- An axis replaces an edge
            @na_pj_sense     = :auto
            na_drawn__after_axis_lock_changed(view)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Can Any Face Being Projected Travel Along This Axis?
        # ------------------------------------------------------------
        def na_pj__axis_usable?(axis)
            sources = @na_pj_sources || []
            return true if sources.empty?

            vector = Na__InsertPrimatives.Na__DrawnGrid__AxisVector(axis)
            sources.any? { |source| Na__InsertPrimatives.Na__Project__Motion(vector, source[:normal]) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | DOWN: Take the Edge Under the Cursor, or Flip
        # ------------------------------------------------------------
        def na_pj__down_key(view)
            candidate = na_pj__edge_under_cursor(view)

            if candidate && !(@na_pj_edge_lock && @na_pj_edge_lock[:key] == candidate[:key])
                na_pj__lock_edge(candidate, view)
            else
                na_pj__flip(view)
            end
        end
        # ---------------------------------------------------------------

        # ON KEY DOWN | ALT Arms Follow, SHIFT+TAB Switches OBJECT Mode
        # ------------------------------------------------------------
        # ALT is swallowed so a bare ALT does not also wake the menu bar.
        # SHIFT+TAB flips once per press through TAB's own held guard, which
        # the shared key-up clears; a held TAB's auto-repeat is swallowed.
        # Not with CTRL down: CTRL+SHIFT is the point-then-grid snap.
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            if key == NA_FOLLOW_ALT_KEY
                unless @na_alt_held
                    @na_alt_held = true
                    na_pj__after_key(view)
                end
                return true
            end

            if key == NA_PJ_TAB_KEY && @na_shift_held && !@na_ctrl_held
                unless @na_tab_held
                    @na_tab_held = true
                    na_pj__toggle_object_mode(view)
                end
                return true
            end

            super
        end
        # ---------------------------------------------------------------

        # ON KEY UP | ALT Released; SHIFT Released Takes ALT With It
        # ------------------------------------------------------------
        def onKeyUp(key, repeat, flags, view)
            if key == NA_FOLLOW_ALT_KEY
                if @na_alt_held
                    @na_alt_held = false
                    na_pj__after_key(view)
                end
                return true
            end

            result       = super
            @na_alt_held = false unless @na_shift_held
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Mouse Flags Are the Truth About SHIFT, and ALT Rides On It
        # ------------------------------------------------------------
        def na_drawn__sync_modifier(flags)
            changed = super

            if @na_alt_held && !@na_shift_held
                @na_alt_held = false
                changed      = true
            end

            changed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Flip OBJECT Mode From the Keyboard
        # ------------------------------------------------------------
        def na_pj__toggle_object_mode(view)
            self.Na__DrawnMode__ToggleToolOption(NA_PJ_OBJECT_OPTION)

            # The right-click menu may be standing open beside the model, and
            # its button would otherwise go on saying the opposite.
            if Na__InsertPrimatives.respond_to?(:Na__RightClickPopup__RefreshOption)
                Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_PJ_OBJECT_OPTION)
            end

            na_pj__after_key(view)
            na_revise__notice(
                na_pj__object_mode? ? 'OBJECT mode — the face stops where it first touches the group or component' :
                                      'PLANE mode — every corner lands on the plane of the face under the cursor'
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Option Flipped From the Menu Drops the Target It Was Read As
        # ------------------------------------------------------------
        def Na__DrawnMode__ToggleToolOption(option_id)
            result        = super
            @na_pj_target = nil
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Read Everything at Once When a Key Changes the Answer
        # ------------------------------------------------------------
        def na_pj__after_key(view)
            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y)
            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnProjectTarget module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PROJECT TARGETS AND DIRECTIONS
# =============================================================================
