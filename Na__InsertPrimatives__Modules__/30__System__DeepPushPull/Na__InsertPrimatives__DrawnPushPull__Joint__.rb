# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL JOINT (SURFACES PUSH AS ONE)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__Joint__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnPushPullJoint
# AUTHOR     : Noble Architecture
# PURPOSE    : The tool's side of a joint push: find the surface under the
#              cursor, preview it, push it, and retype it
# CREATED    : 2026
#
# DESCRIPTION:
# - Hover a face that is part of a smoothed surface and the WHOLE surface
#   lights up, as the Select tool would take it. Grab and drag and it moves as
#   one: every face along its own normal, the corners mitred, the faces round
#   it stretched or walled (the geometry is Na__JointPush__, in the
#   JointGeometry file). Faces selected before the tool starts that touch
#   each other push together the same way (DrawnPushPullPreselect).
# - JOINT SURFACES is an option of the tool (right-click menu), on by
#   default, flipped with SHIFT+TAB, and a Shortcuts command under Extensions.
#   Off, every face is pushed on its own exactly as before 5.2.14.
#
# WHAT A SURFACE TAKES FROM THE SINGLE-FACE TOOL, AND WHAT IT DOES NOT:
# - The drag is measured along the GRABBED face's normal, so the distance
#   on screen is the distance every face of the surface moves. Grid, CTRL,
#   CTRL+SHIFT, the arrows' axis lock, typed distances, retype after placing,
#   double-click repeat and the ghost all work as they do on one face.
# - QUADS keeps the surface's start loop as edges; QUADS inward is a loop cut
#   round the whole surface, where the faces round it run with the push.
# - SHIFT slope and SHIFT+ALT follow are about ONE face's neighbours and stand
#   down on a surface, saying so; SHIFT+TAB first pushes the face alone.
#
# The 2D variant (DrawnPushPull2dTool) works edge-on in an elevation, where a
# surface has no face to hover and its preview is a swept strip. It keeps
# the single face, and its menu does not offer the option.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnPushPull__JointGeometry__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Context__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Joint Preview Constants
    # -----------------------------------------------------------------------------

    NA_JOINT_MAX_LABELS = 6                                                   # <-- Travel labels on a surface; a fascia has a hundred corners

    # endregion -------------------------------------------------------------------


    # =============================================================================
    # MODULE | Deep Push Pull Joint
    # =============================================================================

    module DrawnPushPullJoint

        # -----------------------------------------------------------------------------
        # REGION | Is a Joint Push in Play?
        # -----------------------------------------------------------------------------

        # FUNCTION | Does This Tool Show Faces a Surface Can Be Pushed From?
        # ------------------------------------------------------------
        def na_jp__supported?
            !(defined?(Na__InsertPrimatives::DrawnPushPull2dTool) && is_a?(Na__InsertPrimatives::DrawnPushPull2dTool))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Joint Surfaces On, Here
        # ------------------------------------------------------------
        def na_jp__enabled?
            na_jp__supported? && Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_JOINT_OPTION)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Hovered or Grabbed Face Part of a Joint Push?
        # ------------------------------------------------------------
        def na_jp__active?
            !@na_pp_joint.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read the Surface Under a Hovered or Grabbed Face
        # ------------------------------------------------------------
        # Called from adopt_target on every hover, so the surface is kept: a
        # face of the surface already read, still standing where it stood,
        # costs a lookup. A preselection says itself which faces go together,
        # so while one is in force this leaves @na_pp_joint empty and the
        # preselection's own units carry the plans.
        # ------------------------------------------------------------
        def na_jp__refresh(target)
            @na_pp_joint = nil
            @na_jp_note  = nil
            return nil unless na_jp__enabled?
            return nil if na_pps__active?

            face = target ? target[:face] : nil
            return nil unless face && face.valid?

            cached = @na_jp_cache
            if cached && cached[:face_set][face] &&
               Na__InsertPrimatives.Na__JointPush__Fresh?(cached, target[:transformation])
                @na_pp_joint = cached
                return cached
            end

            faces = Na__InsertPrimatives.Na__JointPush__SurfaceOf(face, NA_JOINT_HOVER_MAX_FACES)

            if faces.nil?
                @na_jp_note = "a surface of over #{NA_JOINT_HOVER_MAX_FACES} faces — select it to push it whole"
                return nil
            end

            return nil if faces.length < 2

            @na_jp_cache = Na__InsertPrimatives.Na__JointPush__Plan(faces, target[:transformation])
            @na_pp_joint = @na_jp_cache
        rescue StandardError => error
            na_drawn__trace("joint surface not read — #{error.message}")
            @na_pp_joint = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The World Distance Every Face of the Surface Moves
        # ------------------------------------------------------------
        def na_jp__distance
            na_drawn__world_travel_distance.to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Drag a Loop Cut Round the Surface?
        # ------------------------------------------------------------
        # QUADS on, travelling in, and every corner able to slide: only then
        # does the offset boundary lie on the faces round the surface, which
        # is where a loop cut's ring has to land.
        # ------------------------------------------------------------
        def na_jp__cut_for?(plan, distance)
            return false unless plan && na_drawn__quad_mode? && distance.to_f < 0.0

            Na__InsertPrimatives.Na__JointPush__Route(plan, distance) == :stretch
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Live Drag's Loop Cut Answer
        # ------------------------------------------------------------
        def na_jp__loop_cut?
            @na_pp_joint ? na_jp__cut_for?(@na_pp_joint, na_jp__distance) : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Push of `distance` Going Into the Solid?
        # ------------------------------------------------------------
        def na_jp__inward?(plan, distance)
            distance.to_f < 0.0 && !plan[:lone]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SHIFT+TAB, the Menu and the Shortcut
        # -----------------------------------------------------------------------------

        # ACTIVATE | Known to the Shortcut Command While Running
        # ------------------------------------------------------------
        def activate
            super
            Na__InsertPrimatives.Na__JointPush__SetActiveTool(self)
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Forgotten Again
        # ------------------------------------------------------------
        def deactivate(view)
            Na__InsertPrimatives.Na__JointPush__SetActiveTool(nil) if Na__InsertPrimatives.Na__JointPush__ActiveTool.equal?(self)
            super
        end
        # ---------------------------------------------------------------

        # ON KEY DOWN | SHIFT+TAB Flips Joint Surfaces; Plain TAB Is Still QUADS
        # ------------------------------------------------------------
        # The plugin's second-switch key (Drawn Volume 5.1.24, Deep Project).
        # One flip per press, through TAB's own held guard; not with CTRL down,
        # where CTRL+SHIFT is the vertex-then-grid snap.
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            tab = self.class::NA_DRAWN_TAB_KEY
            return super unless key == tab && @na_shift_held && !@na_ctrl_held && na_jp__supported?

            unless @na_tab_held
                @na_tab_held = true
                na_jp__toggle_by_key
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Flip Joint Surfaces From the Keyboard
        # ------------------------------------------------------------
        def na_jp__toggle_by_key
            self.Na__DrawnMode__ToggleToolOption(NA_JOINT_OPTION)

            # The menu may be standing open beside the model, and its button
            # would otherwise go on saying the opposite of what the tool does.
            if Na__InsertPrimatives.respond_to?(:Na__RightClickPopup__RefreshOption)
                Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_JOINT_OPTION)
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Any Way the Switch Is Flipped, the Surface Is Read Again
        # ------------------------------------------------------------
        def Na__DrawnMode__ToggleToolOption(option_id)
            result = super
            na_jp__after_switch if option_id.to_s == NA_JOINT_OPTION
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | The 2D Variant's Menu Does Not Offer a Switch It Cannot Use
        # ------------------------------------------------------------
        def Na__DrawnMode__ToolOptions
            options = super
            return options if na_jp__supported?

            options.reject { |option| option[:id] == NA_JOINT_OPTION }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Re-Read the Face in Hand, Mid-Drag Included, and Say So
        # ------------------------------------------------------------
        def na_jp__after_switch
            na_pps__regroup if na_pps__active?
            na_jp__refresh(@na_pp_target) if @na_pp_target

            on = na_jp__enabled?
            na_revise__notice(
                on ? 'JOINT ON — a surface pushes as one, every face along its own normal (SHIFT+TAB)' :
                     'JOINT OFF — one face at a time, as native Push/Pull (SHIFT+TAB)'
            )
            Na__InsertPrimatives.Na__Debug__Puts "DEEP PUSH/PULL: Joint Surfaces #{on ? 'ON' : 'OFF'}"

            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb

            model = Sketchup.active_model
            model.active_view.invalidate if model
            on
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Single-Face Modes Stand Down on a Surface
        # -----------------------------------------------------------------------------

        # FUNCTION | No FOLLOW on a Surface
        # ------------------------------------------------------------
        def na_drawn__follow_mode?
            return false if @na_pp_joint

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why FOLLOW Is Off Here
        # ------------------------------------------------------------
        def na_drawn__follow_reason
            return 'it follows one face — SHIFT+TAB pushes this face alone' if @na_pp_joint && na_drawn__follow_requested?

            super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Shade the Whole Surface Under the Cursor
        # ------------------------------------------------------------
        def na_jp__draw_hover(view, plan)
            colours = self.class
            quads   = na_drawn__quad_mode?

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(
                view, na_jp__triangles_at(plan, plan[:positions]), colours::NA_PP_HOVER_FILL
            )
            na_jp__draw_segments(
                view, plan, plan[:positions],
                quads ? colours::NA_PP_QUAD_BORDER : colours::NA_PP_HOVER_BORDER, quads ? 3 : 2
            )

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, plan[:positions][na_jp__anchor_index(plan)], na_jp__hover_lines(plan, quads)
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Hover Card Says About a Surface
        # ------------------------------------------------------------
        def na_jp__hover_lines(plan, quads)
            lines = ["Surface — #{plan[:count]} faces, #{plan[:area]} m2", Na__InsertPrimatives.Na__DeepPick__PathLabel(@na_pp_target)]
            lines << 'JOINT — pushed as one, every face along its own normal'
            lines << 'QUADS — keeps the start loop' if quads
            lines << "#{plan[:clamped]} sharp corner(s) held to #{NA_JOINT_MAX_MITRE.to_i}x the push" if plan[:clamped].to_i > 0
            lines << "Cannot push it — #{plan[:problem]}" if plan[:problem]
            lines << (na_pps__active? ? 'SHIFT+TAB pushes each selected face on its own' : 'SHIFT+TAB pushes this face alone')
            lines
        end
        # ---------------------------------------------------------------

        # FUNCTION | Preview the Surface at Its Pushed Position
        # ------------------------------------------------------------
        # The same picture the single face paints, drawn from the plan: the
        # start boundary, the surface where it is going, the rungs between,
        # the travel arrow and the labels. Into a solid it is the volume
        # removed, in cutter red through the model; a loop cut is the ring.
        # ------------------------------------------------------------
        def na_jp__draw_push(view, plan)
            colours  = self.class
            quads    = na_drawn__quad_mode?
            distance = na_jp__distance

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d) && distance.abs > 0.0
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, na_jp__triangles_at(plan, plan[:positions]), colours::NA_PP_HOVER_FILL)
                na_jp__draw_segments(view, plan, plan[:positions], quads ? colours::NA_PP_QUAD_BORDER : colours::NA_PP_HOVER_BORDER, quads ? 3 : 1)
                return
            end

            moved = Na__InsertPrimatives.Na__JointPush__Moved(plan, distance)

            if na_jp__cut_for?(plan, distance)
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, na_jp__triangles_at(plan, plan[:positions]), colours::NA_PP_HOVER_FILL)
                na_jp__draw_segments(view, plan, plan[:positions], colours::NA_PP_HOVER_BORDER, 1)
                na_jp__draw_rungs(view, plan, moved, colours::NA_PP_QUAD_BORDER)
                na_jp__draw_segments(view, plan, moved, colours::NA_PP_QUAD_BORDER, 3)
            else
                na_jp__draw_segments(
                    view, plan, plan[:positions],
                    quads ? colours::NA_PP_QUAD_BORDER : colours::NA_PP_HOVER_BORDER, quads ? 3 : 1
                )

                if na_jp__inward?(plan, distance)
                    na_jp__draw_xray(view, plan, moved) || na_jp__draw_result(view, plan, moved, NA_DRAWN_CUTTER_FILL_COLOR, NA_DRAWN_CUTTER_BORDER_COLOR)
                else
                    na_jp__draw_result(view, plan, moved, colours::NA_PP_RESULT_FILL, colours::NA_PP_RESULT_BORDER)
                end
            end

            na_drawn__draw_travel_arrow(view, na_drawn__push_offset_vector)
            na_jp__draw_labels(view, plan, moved, distance)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Moved Surface, Its Outline and Its Rungs, Depth-Tested
        # ------------------------------------------------------------
        def na_jp__draw_result(view, plan, moved, fill, border)
            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, na_jp__triangles_at(plan, moved), fill)
            na_jp__draw_segments(view, plan, moved, border, 2)
            na_jp__draw_rungs(view, plan, moved, border)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Push Into the Solid, Drawn Through Everything
        # ------------------------------------------------------------
        # The joint version of Na__DrawnPreview__DrawPrismOnTop: the moved
        # surface, its walls and its rungs in screen space with no depth test,
        # so the volume removed reads through the faces that would hide it.
        # false when a point is behind a perspective camera, for the caller's
        # depth-tested fallback.
        # ------------------------------------------------------------
        def na_jp__draw_xray(view, plan, moved)
            start   = plan[:positions]
            project = lambda do |points|
                points.empty? ? [] : Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, points)
            end

            cap   = project.call(plan[:triangles].flat_map { |triangle| triangle.map { |i| moved[i] } })
            far   = project.call(plan[:segments].flat_map { |a, b| [moved[a], moved[b]] })
            near  = project.call(plan[:segments].flat_map { |a, b| [start[a], start[b]] })
            walls = project.call(plan[:segments].flat_map { |a, b| [start[a], start[b], moved[b], moved[a]] })
            rungs = project.call(na_jp__boundary_ids(plan).flat_map { |i| [start[i], moved[i]] })
            return false unless cap && far && near && walls && rungs

            view.drawing_color = NA_DRAWN_CUTTER_XRAY_FILL
            view.draw2d(GL_TRIANGLES, cap) unless cap.empty?
            view.draw2d(GL_QUADS, walls)   unless walls.empty?

            view.line_stipple  = ''
            view.drawing_color = NA_DRAWN_CUTTER_BORDER_COLOR
            view.line_width    = 2
            view.draw2d(GL_LINES, far)   unless far.empty?
            view.line_width    = 1
            view.draw2d(GL_LINES, near)  unless near.empty?
            view.draw2d(GL_LINES, rungs) unless rungs.empty?
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Surface's Triangles at a Set of Positions
        # ------------------------------------------------------------
        def na_jp__triangles_at(plan, points)
            plan[:triangles].map { |triangle| triangle.map { |i| points[i] } }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Surface's Boundary Drawn as Lines at a Set of Positions
        # ------------------------------------------------------------
        def na_jp__draw_segments(view, plan, points, color, width)
            return if plan[:segments].empty?

            lines = plan[:segments].flat_map { |a, b| [points[a], points[b]] }

            view.line_stipple  = ''
            view.line_width    = width
            view.drawing_color = color
            view.draw(GL_LINES, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(lines))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Line From Every Boundary Corner to Where It Goes
        # ------------------------------------------------------------
        def na_jp__draw_rungs(view, plan, moved, color)
            ids = na_jp__boundary_ids(plan)
            return if ids.empty?

            lines = ids.flat_map { |i| [plan[:positions][i], moved[i]] }

            view.line_stipple  = ''
            view.line_width    = 1
            view.drawing_color = color
            view.draw(GL_LINES, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(lines))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Corner on the Surface's Boundary, Once
        # ------------------------------------------------------------
        def na_jp__boundary_ids(plan)
            plan[:boundary_ids] ||= plan[:segments].flat_map { |a, b| [a, b] }.uniq
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Corner the Card Hangs From
        # ------------------------------------------------------------
        # The grabbed face's first corner when the grabbed face is in this
        # surface, so the card sits where the user is looking; otherwise the
        # surface's own first face.
        # ------------------------------------------------------------
        def na_jp__anchor_index(plan)
            face = @na_pp_target ? @na_pp_target[:face] : nil
            row  = plan[:rows].find { |candidate| candidate[:face] == face } || plan[:rows].first
            row[:outer].first
        end
        # ---------------------------------------------------------------

        # FUNCTION | Label the Travel, and the Card Saying What the Push Will Do
        # ------------------------------------------------------------
        # Every travel edge of a face is labelled; a surface has a corner
        # every few degrees round a curve, so at most NA_JOINT_MAX_LABELS of
        # them are, spread along the boundary, before the overlap cull.
        # ------------------------------------------------------------
        def na_jp__draw_labels(view, plan, moved, distance)
            locked = na_drawn__locked?(:d)
            text   = Na__InsertPrimatives.Na__DrawnPreview__DimensionText(@na_size_d, locked)
            color  = @na_axis_lock ? Na__InsertPrimatives.Na__DrawnPreview__AxisColor(@na_axis_lock) :
                                     Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(locked)
            ids    = na_jp__boundary_ids(plan)
            step   = [(ids.length.to_f / NA_JOINT_MAX_LABELS).ceil, 1].max
            placed = []

            ids.each_with_index do |i, k|
                next unless (k % step).zero?
                next unless na_drawn__claim_label_slot(view, plan[:positions][i], moved[i], placed)

                Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(view, plan[:positions][i], moved[i], text, color)
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, moved[na_jp__anchor_index(plan)], na_jp__card_lines(plan, distance)
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Card's Lines for a Push of `distance`
        # ------------------------------------------------------------
        def na_jp__card_lines(plan, distance)
            mm    = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
            quads = na_drawn__quad_mode?

            lines =
                if na_jp__cut_for?(plan, distance)
                    ["Loop cut #{mm} mm inset round the surface"]
                else
                    ["Push #{mm} mm#{na_jp__inward?(plan, distance) ? ' in' : ''}#{quads ? '  (quads)' : ''}"]
                end

            lines << "Surface — #{plan[:count]} faces joined, #{plan[:area]} m2"
            lines << na_jp__route_words(plan, distance) unless na_jp__cut_for?(plan, distance)

            if @na_axis_lock
                along = Na__InsertPrimatives.Na__DrawnFormat__Mm(distance).abs
                lines << "along #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]} · #{along} mm on the grabbed face's normal"
            end

            problem = Na__InsertPrimatives.Na__JointPush__Problem(plan, distance)
            lines << "NOT PLACEABLE — #{problem}" if problem
            lines
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Push Does to the Faces Round the Surface, in Words
        # ------------------------------------------------------------
        def na_jp__route_words(plan, distance)
            distance = 1.0 if distance.to_f.abs < 1.0                         # <-- The first frames of a drag read as an inch, not as nothing
            case Na__InsertPrimatives.Na__JointPush__Route(plan, distance)
            when :stretch then 'the faces round it stretch to meet it'
            when :thicken then 'a lone surface — thickened, the original kept as its back'
            else               'new sides where the faces round it cannot follow'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Surface's Preview Occupies, for the Extents
        # ------------------------------------------------------------
        def na_jp__preview_points(plan)
            points   = plan[:positions]
            distance = na_jp__distance
            return points unless @na_state == :picking_depth && distance.abs > 0.0

            points + Na__InsertPrimatives.Na__JointPush__Moved(plan, distance)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Bar
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Line on a Surface
        # ------------------------------------------------------------
        def na_jp__status_detail
            plan  = @na_pp_joint
            quads = na_drawn__quad_mode? ? ' QUADS' : ''

            if @na_state == :picking_depth
                mm       = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
                text     = na_drawn__locked?(:d) ? "[#{mm}]" : mm.to_s
                distance = na_jp__distance

                if Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                    problem = Na__InsertPrimatives.Na__JointPush__Problem(plan, distance)
                    return "Push #{text} mm — not placeable: #{problem}" if problem
                end

                return "Loop cut #{text} mm inset round the surface — release or click to cut" if na_jp__loop_cut?

                return "Push#{quads} #{text} mm, surface of #{plan[:count]} faces — " \
                       "#{na_jp__route_words(plan, distance)} — release or click to place"
            end

            "Surface #{plan[:count]} faces #{plan[:area]} m2 — click to grab it, it pushes as one " \
                "(SHIFT+TAB: this face alone)#{quads}#{na_drawn__focus_hint}#{na_revise__status_hint}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Commit
        # -----------------------------------------------------------------------------

        # FUNCTION | A Grabbed Surface Is Pushed Whole
        # ------------------------------------------------------------
        def na_drawn__commit_push(view)
            return na_jp__commit_push(view) if @na_pp_joint && !na_pps__active?

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push the Grabbed Surface
        # ------------------------------------------------------------
        # The single-face commit's checks and reports, in the same order, with
        # the joint geometry where pushpull was.
        # ------------------------------------------------------------
        def na_jp__commit_push(view)
            target = @na_pp_target
            plan   = @na_pp_joint

            unless target && target[:face] && target[:face].valid? && plan && plan[:faces].all?(&:valid?)
                UI.beep
                Sketchup::set_status_text('That surface is no longer available', SB_PROMPT)
                na_drawn__reset_pick_state
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                na_drawn__trace('surface placement refused — zero distance')
                Sketchup::set_status_text('No push distance — drag further or type one', SB_PROMPT)
                return false
            end

            unless na_drawn__axis_lock_usable?
                UI.beep
                Sketchup::set_status_text('This face cannot travel along the locked axis', SB_PROMPT)
                return false
            end

            distance = na_jp__distance
            problem  = Na__InsertPrimatives.Na__JointPush__Problem(plan, distance)

            if problem
                UI.beep
                na_revise__notice("Not placed — #{problem}")
                return false
            end

            model    = Sketchup.active_model
            cutting  = na_jp__cut_for?(plan, distance)
            snapshot = na_jp__snapshot(plan, target, model)
            stats    = na_jp__execute(model, target, plan, distance, cutting)

            unless stats
                UI.beep
                Sketchup::set_status_text("Push failed: #{@na_pp_last_error}", SB_PROMPT)
                na_jp__report_failure(target, plan, distance)
                na_revise__forget
                na_revise__load_memory                                        # <-- The aborted operation rolled its memory write back too
                @na_jp_cache = nil
                na_drawn__reset_pick_state
                return false
            end

            na_jp__capture(target, plan, snapshot, cutting)
            na_jp__log(target, plan, distance, stats)
            na_jp__warn_quads(stats, cutting)

            @na_jp_cache = nil                                                # <-- The surface has moved or been rebuilt
            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Joint Push Inside the Surface's Own Editing Context
        # ------------------------------------------------------------
        # The single-face commit's front door (enter, one operation, restore;
        # see na_drawn__execute_push for why), with two joint additions:
        # - the faces are found again inside the open group when opening it
        #   handed back a fresh definition, by the world point inside each one;
        # - the plan is read AGAIN inside, where the reported space is world,
        #   so the geometry's maths run on the coordinates the model will take.
        # Returns the geometry's report, or nil with @na_pp_last_error set.
        # ------------------------------------------------------------
        def na_jp__execute(model, target, plan, distance, cutting)
            @na_pp_last_error = nil

            instances   = Na__InsertPrimatives.Na__DeepPick__Instances(target[:path])
            target_path = instances.empty? ? nil : instances
            anchors     = na_jp__world_anchors(plan)
            entered     = false
            previous    = nil
            selected    = Na__InsertPrimatives.Na__DeepPick__FocusSnapshot(model)

            if model.respond_to?(:active_path=)
                begin
                    previous = model.active_path
                    unless Na__InsertPrimatives.Na__DeepPick__SameContext?(previous, target_path)
                        model.active_path = target_path
                        entered = true
                        na_drawn__trace("entered context #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}")
                    end
                rescue StandardError => error
                    entered = false
                    na_drawn__trace("context open failed (#{error.message}) — editing from outside")
                end
            end

            op_name = cutting ? 'Deep Push Pull (Joint Loop Cut)' : 'Deep Push Pull (Joint Surface)'

            # The undo chaining is the single-face commit's: transparent both
            # ways only when a context was entered, so enter-push-restore
            # unwinds as one Ctrl+Z and nothing else is ever merged into it.
            if entered
                model.start_operation(op_name, true, true, true)
            else
                model.start_operation(op_name, true)
            end

            stats = nil

            begin
                faces = entered ? na_jp__faces_in_open(model, plan, anchors) : plan[:faces]
                raise 'the surface could not be found again inside its group' unless faces && faces.none?(&:nil?) && faces.all?(&:valid?)

                now = Na__InsertPrimatives.Na__JointPush__Plan(faces, entered ? Geom::Transformation.new : plan[:xform])
                raise 'the surface could not be read again' unless now

                problem = Na__InsertPrimatives.Na__JointPush__Problem(now, distance)
                raise problem if problem

                entities = faces.first.parent.entities
                stats    = Na__InsertPrimatives.Na__JointPush__Apply(entities, now, distance, na_drawn__quad_mode?, cutting)

                if cutting && (stats[:quad].nil? || stats[:quad][:kept].to_i.zero?)
                    raise 'no loop cut — the faces round the surface would not take the ring'
                end

                Na__InsertPrimatives.Na__DeepPick__InvalidateDefinitions(target[:path]) unless entered

                # The distance a double-click on the next face will repeat,
                # inside the operation so it rides in this undo step.
                na_revise__remember(model, na_drawn__signed_d)

                model.commit_operation
            rescue StandardError => error
                model.abort_operation
                @na_pp_last_error = error.message
                na_drawn__trace("joint push raised: #{error.message}")
                stats = nil
            end

            if entered
                na_drawn__restore_context(model, previous)
                Na__InsertPrimatives.Na__DeepPick__FocusRestore(model, selected)
            end

            stats
        end
        # ---------------------------------------------------------------

        # FUNCTION | A World Point Inside Each Face, Read Before the Group Opens
        # ------------------------------------------------------------
        def na_jp__world_anchors(plan)
            plan[:rows].map do |row|
                interior = Na__InsertPrimatives.Na__SlopePush__InteriorPoint(row[:face])
                [interior ? interior.transform(plan[:xform]) : nil, row[:normal]]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Surface's Faces in the Context Now Open
        # ------------------------------------------------------------
        # The faces themselves when they belong to it — the usual case. When
        # opening the group made it unique, the objects picked a moment ago
        # belong to the copies left behind, and each face is found again by
        # the world point inside it (the open context reports world).
        # ------------------------------------------------------------
        def na_jp__faces_in_open(model, plan, anchors)
            owner = model.active_entities.parent
            return plan[:faces] if plan[:faces].all? { |face| face.valid? && face.parent == owner }

            candidates = model.active_entities.grep(Sketchup::Face)

            anchors.map do |point, normal|
                next nil unless point && normal

                candidates.find do |face|
                    face.valid? && face.normal.dot(normal) > NA_JOINT_SAME_NORMAL &&
                        face.classify_point(point) == Sketchup::Face::PointInside
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push One Preselected Surface Inside the Batch's Operation
        # ------------------------------------------------------------
        # A preselection lives in the user's open context, so nothing is
        # entered and the reported space is world. The plan is read again at
        # this moment, after any push earlier in the batch, so it stands on
        # what is there now. Raises, and the batch rolls back whole.
        # ------------------------------------------------------------
        def na_jp__apply_in_batch(model, recipe, distance)
            faces = recipe[:plan][:faces]
            raise 'A push removed a selected face; the batch was cancelled' unless faces.all?(&:valid?)

            plan = Na__InsertPrimatives.Na__JointPush__Plan(faces, Geom::Transformation.new)
            raise 'A selected surface could not be read' unless plan

            problem = Na__InsertPrimatives.Na__JointPush__Problem(plan, distance)
            raise problem if problem

            cutting = na_jp__cut_for?(plan, distance)
            stats   = Na__InsertPrimatives.Na__JointPush__Apply(faces.first.parent.entities, plan, distance, na_drawn__quad_mode?, cutting)

            if cutting && (stats[:quad].nil? || stats[:quad][:kept].to_i.zero?)
                raise 'A selected surface could not produce a loop cut'
            end

            na_revise__remember(model, na_drawn__signed_d)
            na_jp__log(recipe[:unit][:targets].first, plan, distance, stats)

            # A rebuilt surface is new faces; the selection lost the old ones
            # with them, so the new ones are selected in their place.
            (@na_pps_reselect ||= []).concat(stats[:faces] || [])

            record = na_jp__record(recipe[:unit][:targets].first, plan, recipe[:snapshot], cutting)
            raise 'Could not record a selected surface' unless record

            record.merge(:ghost => recipe[:ghost], :targets => recipe[:unit][:targets])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say a Quad Line or Loop Cut That Built Nothing
        # ------------------------------------------------------------
        def na_jp__warn_quads(stats, cutting)
            return unless na_drawn__quad_mode? && !cutting

            quad = stats[:quad]
            return unless quad.nil? || quad[:kept].to_i.zero? || quad[:misplaced]

            UI.beep
            Sketchup::set_status_text('Surface pushed, but the quad line built nothing — see the console', SB_PROMPT)
            @na_last_status_text = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Joint Push
        # ------------------------------------------------------------
        def na_jp__log(target, plan, distance, stats)
            route = case stats[:route]
                    when :stretch then 'stretch — the faces round it followed, nothing created'
                    when :thicken then 'thicken — a lone surface, the original kept as its back'
                    else               'rebuild — new sides where a corner had to stay'
                    end

            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts(
                na_revise__replaying? ? 'DEEP PUSH/PULL ADJUSTED — JOINT SURFACE (retyped distance)' : 'DEEP PUSH/PULL APPLIED — JOINT SURFACE'
            )
            Na__InsertPrimatives.Na__Debug__Puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "Surface: #{plan[:count]} faces, #{plan[:area]} m2"
            Na__InsertPrimatives.Na__Debug__Puts "Push   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(distance).abs}mm #{distance < 0.0 ? 'in' : 'out'}, every face along its own normal"
            Na__InsertPrimatives.Na__Debug__Puts "Route  : #{stats[:cut] ? 'loop cut round the surface' : route}"
            Na__InsertPrimatives.Na__Debug__Puts "Corners: #{stats[:moved]} slid, #{plan[:clamped]} sharp mitre(s) capped" unless stats[:cut]
            unless stats[:route] == :stretch || stats[:cut]
                Na__InsertPrimatives.Na__Debug__Puts "Faces  : #{stats[:rebuilt]} rebuilt, #{stats[:walls]} wall(s), #{stats[:healed]} healed flat, " \
                                                     "#{stats[:cancelled]} taken back, #{stats[:softened]} softened"
            end
            Na__InsertPrimatives.Na__Debug__Puts "Folded : #{stats[:folded]} fold line(s) keep bent faces flat" if stats[:folded].to_i > 0
            Na__InsertPrimatives.Na__Debug__Puts "Instances affected: #{target[:shared_count]}"
            quad = stats[:quad]
            Na__InsertPrimatives.Na__Debug__Puts "Quads  : #{quad ? "#{quad[:kept]} edge(s) kept, #{quad[:swept]} swept" : 'off'}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say Out Loud Why a Joint Push Was Refused
        # ------------------------------------------------------------
        def na_jp__report_failure(target, plan, distance)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts 'DEEP PUSH/PULL REFUSED — JOINT SURFACE'
            Na__InsertPrimatives.Na__Debug__Puts "Reason : #{@na_pp_last_error}"
            Na__InsertPrimatives.Na__Debug__Puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "Surface: #{plan[:count]} faces, route #{Na__InsertPrimatives.Na__JointPush__Route(plan, distance)}"
            Na__InsertPrimatives.Na__Debug__Puts "Push   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(distance)}mm"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA PUSH/PULL: joint push refused, and the report itself failed (#{error.message})"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Retype, Repeat and the Ghost
        # -----------------------------------------------------------------------------

        # FUNCTION | Read Every Face's Own Space BEFORE Anything Moves It
        # ------------------------------------------------------------
        # The single face's snapshot, once per face of the surface: a point
        # strictly inside it and its normal, in the space it reports in the
        # user's own context, which is the space it reports in again once an
        # undo has put the user back there.
        # ------------------------------------------------------------
        def na_jp__snapshot(plan, target, model)
            faces  = plan[:faces]
            parent = faces.first.parent

            {
                :entities  => parent.respond_to?(:entities) ? parent.entities : model.active_entities,
                :faces     => faces.map do |face|
                    { :face => face, :interior => Na__InsertPrimatives.Na__SlopePush__InteriorPoint(face), :normal => face.normal.clone }
                end,
                :driver    => faces.index(target[:face]) || 0,
                :user_path => model.respond_to?(:active_path) ? model.active_path : nil
            }
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arm the Retype for a Placed Surface
        # ------------------------------------------------------------
        def na_jp__capture(target, plan, snapshot, cutting)
            record = snapshot ? na_jp__record(target, plan, snapshot, cutting) : nil
            return na_revise__forget unless record

            na_revise__arm(record)
        rescue StandardError => error
            na_drawn__trace("surface retype not armed — #{error.message}")
            na_revise__forget
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Record a Surface's Retype Is Rebuilt From
        # ------------------------------------------------------------
        # :cut stays false even for a loop cut: on a face record it offers
        # *N / /N arrays, which are a single face's. :joint_cut says it here.
        # ------------------------------------------------------------
        def na_jp__record(target, plan, snapshot, cutting)
            entities = na_jp__live_entities(snapshot)
            return nil unless entities

            replaying = @na_revise_replaying
            anchor    = replaying ? replaying[:anchor_sign].to_f : @na_sign_d.to_f
            ghost     = replaying && replaying[:ghost] && replaying[:ghost][:joint] ? replaying[:ghost] : na_jp__ghost(plan, cutting)

            {
                :kind        => :joint,
                :target      => target,
                :entities    => entities,
                :faces       => snapshot[:faces],
                :driver      => snapshot[:driver],
                :user_path   => snapshot[:user_path],
                :counts      => [[entities, na_revise__entity_count(entities)]],
                :ops         => 1,
                :size        => @na_size_d.to_f.abs,
                :sign        => @na_sign_d.to_f,
                :value       => @na_size_d.to_f.abs * @na_sign_d.to_f,
                :anchor_sign => anchor,
                :axis_lock   => @na_axis_lock,
                :slope       => nil,
                :slope_mode  => false,
                :follow      => false,
                :quad        => na_drawn__quad_mode?,
                :cut         => false,
                :joint_cut   => cutting ? true : false,
                :ghost       => ghost
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Collection a Placed Surface Lives In Now
        # ------------------------------------------------------------
        def na_jp__live_entities(snapshot)
            face = snapshot[:faces].map { |row| row[:face] }.find { |candidate| candidate && candidate.valid? }

            if face
                parent = face.parent
                return parent.entities if parent.respond_to?(:entities)
            end

            na_revise__entity_count(snapshot[:entities]).nil? ? nil : snapshot[:entities]
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Ghost of a Surface Push Draws, Frozen at Placing
        # ------------------------------------------------------------
        def na_jp__ghost(plan, cutting)
            {
                :joint       => {
                    :positions => plan[:positions].map(&:clone),
                    :units     => plan[:units].map { |unit| unit ? unit.clone : nil },
                    :triangles => plan[:triangles],
                    :segments  => plan[:segments].map { |a, b| [a, b] },
                    :anchor    => na_jp__anchor_index(plan),
                    :lone      => plan[:lone]
                },
                :axis_factor => na_drawn__axis_travel_factor,
                :quad        => na_drawn__quad_mode?,
                :cut         => cutting ? true : false
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find a Placed Surface Again Where the Undo Put It Back
        # ------------------------------------------------------------
        # Every face by the point inside it: the recorded object first (one
        # test, and the answer whenever the push only moved it), then the
        # faces of the collection sharing its normal. One face not found and
        # nothing is rebuilt; the shared flow puts the push back with Redo.
        # ------------------------------------------------------------
        def na_revise__reacquire(record)
            return super unless record[:kind] == :joint

            entities = na_jp__live_entities(record)
            return nil unless entities

            pool  = nil
            faces = record[:faces].map do |row|
                face = row[:face]
                next face if face && face.valid? && face.classify_point(row[:interior]) == Sketchup::Face::PointInside

                pool ||= entities.grep(Sketchup::Face)
                pool.find do |candidate|
                    candidate.valid? && candidate.normal.dot(row[:normal]) > NA_JOINT_SAME_NORMAL &&
                        candidate.classify_point(row[:interior]) == Sketchup::Face::PointInside
                end
            end

            return nil if faces.include?(nil) || faces.uniq.length != faces.length

            driver = faces[record[:driver].to_i] || faces.first
            target = record[:target].merge(:face => driver)
            plan   = Na__InsertPrimatives.Na__JointPush__Plan(faces, target[:transformation])
            return nil unless plan

            path = Na__InsertPrimatives.Na__DeepPick__ContextPath
            target.merge(
                :kind    => :joint,
                :plan    => plan,
                :targets => faces.map { |face| face == driver ? target : Na__InsertPrimatives.Na__DeepPick__BuildTarget(face, path, nil) }
            )
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push the Surface Again at a Signed Distance
        # ------------------------------------------------------------
        def na_revise__rebuild(record, target, value, view)
            return super unless record[:kind] == :joint

            placed = false

            na_revise__wearing(record, target, value) do
                @na_pp_joint = target[:plan]
                placed       = na_drawn__commit_push(view)
            end

            placed ? true : false
        ensure
            @na_pp_joint = nil if record && record[:kind] == :joint && @na_state == :idle
        end
        # ---------------------------------------------------------------

        # FUNCTION | *N and /N Array One Face's Loop Cut, Not a Surface
        # ------------------------------------------------------------
        def na_revise__parse_retype(text, record)
            if record && record[:kind] == :joint && Na__InsertPrimatives.Na__QuadRings__ArrayEntry?(text)
                raise ArgumentError, '*N and /N array a single face\'s loop cut — a surface takes a distance'
            end

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Leading Sign Means for a Placed Surface
        # ------------------------------------------------------------
        def na_revise__sign_hint
            return ' (- reverses)' if @na_revise_record && @na_revise_record[:kind] == :joint

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Surface Swept to an Interpolated Distance
        # ------------------------------------------------------------
        def na_revise__draw_ghost(view, ghost, value, from_value, to_value)
            return super unless ghost && ghost[:joint]

            data    = ghost[:joint]
            colours = self.class
            factor  = ghost[:axis_factor].to_f
            factor  = 1.0 if factor.abs < 0.0001
            world   = value.to_f / factor
            moved   = Na__InsertPrimatives.Na__JointPush__Moved(data, world)
            start   = data[:positions]
            quads   = ghost[:quad] ? true : false

            na_jp__draw_ghost_lines(view, data, start, quads ? colours::NA_PP_QUAD_BORDER : colours::NA_PP_HOVER_BORDER, 1)

            if ghost[:cut]
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, data[:triangles].map { |t| t.map { |i| start[i] } }, colours::NA_PP_HOVER_FILL)
                na_jp__draw_ghost_rungs(view, data, start, moved, colours::NA_PP_QUAD_BORDER)
                na_jp__draw_ghost_lines(view, data, moved, colours::NA_PP_QUAD_BORDER, 3)
            else
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, data[:triangles].map { |t| t.map { |i| moved[i] } }, colours::NA_PP_RESULT_FILL)
                na_jp__draw_ghost_rungs(view, data, start, moved, colours::NA_PP_RESULT_BORDER)
                na_jp__draw_ghost_lines(view, data, moved, colours::NA_PP_RESULT_BORDER, 2)
            end

            from_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(from_value).abs
            to_mm   = Na__InsertPrimatives.Na__DrawnFormat__Mm(to_value).abs

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, moved[data[:anchor].to_i] || moved.first,
                ["#{ghost[:cut] ? 'Loop cut' : 'Push'} #{from_mm} → #{to_mm} mm  (surface)"],
                14, -26, NA_DRAWN_TEXT_ACCENT_COLOR
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Ghost's Boundary at a Set of Positions
        # ------------------------------------------------------------
        def na_jp__draw_ghost_lines(view, data, points, color, width)
            return if data[:segments].empty?

            view.line_stipple  = ''
            view.line_width    = width
            view.drawing_color = color
            view.draw(GL_LINES, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(data[:segments].flat_map { |a, b| [points[a], points[b]] }))
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Ghost's Rungs
        # ------------------------------------------------------------
        def na_jp__draw_ghost_rungs(view, data, start, moved, color)
            ids = data[:segments].flat_map { |a, b| [a, b] }.uniq
            return if ids.empty?

            view.line_stipple  = ''
            view.line_width    = 1
            view.drawing_color = color
            view.draw(GL_LINES, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(ids.flat_map { |i| [start[i], moved[i]] }))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Ghost Occupies at a Distance, for the Extents
        # ------------------------------------------------------------
        def na_revise__ghost_points(ghost, value)
            return super unless ghost && ghost[:joint]

            data   = ghost[:joint]
            factor = ghost[:axis_factor].to_f
            factor = 1.0 if factor.abs < 0.0001

            data[:positions] + Na__InsertPrimatives.Na__JointPush__Moved(data, value.to_f / factor)
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullJoint module


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Points — the Shortcut Command
    # -----------------------------------------------------------------------------

    # FUNCTION | The Running Push/Pull, While There Is One
    # ------------------------------------------------------------
    def self.Na__JointPush__ActiveTool
        tool = @na_joint_active_tool
        tool.is_a?(Na__InsertPrimatives::DrawnPushPullTool) ? tool : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remember (or Forget) the Running Push/Pull
    # ------------------------------------------------------------
    def self.Na__JointPush__SetActiveTool(tool)
        @na_joint_active_tool = tool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is Joint Surfaces On? (Ticks the Extensions Menu Entry)
    # ------------------------------------------------------------
    def self.Na__PushPull__JointOn?
        Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_JOINT_OPTION)
    end
    # ---------------------------------------------------------------

    # FUNCTION | Flip Joint Surfaces (Extensions Menu, Shortcut)
    # ------------------------------------------------------------
    # Through the running tool when there is one, so the surface in hand is
    # read again at once; otherwise the stored switch alone.
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__TogglePushPullJoint
        tool = Na__InsertPrimatives.Na__JointPush__ActiveTool

        if tool
            tool.Na__DrawnMode__ToggleToolOption(NA_JOINT_OPTION)
        else
            Na__InsertPrimatives.Na__ToolOptions__Toggle(NA_JOINT_OPTION)
            Sketchup::set_status_text(
                Na__InsertPrimatives.Na__PushPull__JointOn? ? 'Deep Push/Pull Joint Surfaces: on — a surface pushes as one' :
                                                              'Deep Push/Pull Joint Surfaces: off — one face at a time',
                SB_PROMPT
            )
        end

        Na__InsertPrimatives.Na__RightClickPopup__RefreshOption(NA_JOINT_OPTION) if Na__InsertPrimatives.respond_to?(:Na__RightClickPopup__RefreshOption)
        Na__InsertPrimatives.Na__PushPull__JointOn?
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL JOINT
# =============================================================================
