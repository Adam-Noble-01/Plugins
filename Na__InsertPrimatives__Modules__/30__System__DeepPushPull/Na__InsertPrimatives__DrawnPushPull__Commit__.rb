# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL COMMIT
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__Commit__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnPushPullCommit
# AUTHOR     : Noble Architecture
# PURPOSE    : Commit and execute a grabbed-face push inside nested context
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'
require_relative 'Na__InsertPrimatives__DrawnPushPull__QuadRing__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnEdgeLoops__'

module Na__InsertPrimatives

    module DrawnPushPullCommit

        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit
        # -----------------------------------------------------------------------------

        # FUNCTION | Push the Grabbed Face
        # The distance handed to pushpull is LOCAL to the face's own definition,
        # so the world travel is divided by the scale the instance path applies
        # along that normal. Without it a push inside a scaled component would
        # overshoot by exactly that scale factor.
        # ------------------------------------------------------------
        def na_drawn__commit_push(view)
            target = @na_pp_target

            unless target && target[:face] && target[:face].valid?
                UI.beep
                Sketchup::set_status_text('That face is no longer available', SB_PROMPT)
                na_drawn__reset_pick_state
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                na_drawn__trace('placement refused — zero distance')
                Sketchup::set_status_text('No push distance — drag further or type one', SB_PROMPT)
                return false
            end

            unless na_drawn__axis_lock_usable?
                UI.beep
                Sketchup::set_status_text('This face cannot travel along the locked axis', SB_PROMPT)
                return false
            end

            world_travel = na_drawn__world_travel_distance
            local_offset = na_drawn__local_offset_vector(target)

            unless local_offset
                UI.beep
                Sketchup::set_status_text('That face could not be measured in its own space', SB_PROMPT)
                return false
            end

            model    = Sketchup.active_model
            cutting  = na_drawn__loop_cut_mode?                               # <-- Read before the commit; reporting below needs it
            sloped   = na_drawn__slope_mode?

            # Read while the face is still untouched. Nothing below can ask the
            # face where it started once pushpull has moved it, and that is the
            # one thing a retype of the distance needs — see the Revise module.
            snapshot = na_revise__snapshot(target, model)

            unless na_drawn__execute_push(model, target, local_offset)
                UI.beep
                Sketchup::set_status_text("Push failed: #{@na_pp_last_error}", SB_PROMPT)
                na_drawn__report_failure(target, local_offset, sloped)
                na_revise__forget
                na_revise__load_memory                                        # <-- The aborted operation rolled its memory write back too
                na_drawn__reset_pick_state
                return false
            end

            # Arm the measurements box to accept a new distance for the push
            # that was just placed, the way native Push/Pull and Joint Push/Pull
            # both do. Armed here, while every number this push was made from is
            # still in scope, and read back by the retype, the repeat and the
            # ghost — see DrawnReviseShared and the Revise module.
            na_revise__capture(target, snapshot, local_offset, sloped, cutting)

            na_drawn__trace("placed #{Na__InsertPrimatives.Na__DrawnFormat__Mm(world_travel).abs}mm")
            na_drawn__log_push(target, world_travel, sloped)

            # A ring that went in and came straight back out is a silent failure
            # otherwise: the push looks right and the quad line simply is not
            # there. Say so where the user is already looking.
            if @na_pp_quad_stats && @na_pp_quad_stats[:misplaced]
                UI.beep
                Sketchup::set_status_text('Push placed, but the quad ring could not be positioned — see the console', SB_PROMPT)
                @na_last_status_text = nil
            end

            # A loop cut that kept nothing did nothing at all — the solid is
            # untouched and no line was left. Without this the gesture reads as
            # having simply been ignored, which is the hardest kind of failure
            # to diagnose from the viewport.
            if cutting && (@na_pp_quad_stats.nil? || @na_pp_quad_stats[:kept].to_i.zero?)
                UI.beep
                Sketchup::set_status_text(
                    'No loop cut — the faces around this one are not a clean sweep of it',
                    SB_PROMPT
                )
                @na_last_status_text = nil
            end

            # And the same for the outward ring. It only ever announced itself
            # when it landed in the wrong SPACE, so a ring that landed on top of
            # edges that were already there — building nothing, reporting them
            # as kept — passed in silence. A quad line that does not appear is
            # exactly as broken as one that lands in the wrong place.
            if na_drawn__quad_mode? && !cutting &&
               (@na_pp_quad_stats.nil? || @na_pp_quad_stats[:kept].to_i.zero?)
                UI.beep
                Sketchup::set_status_text(
                    'Push placed, but the quad line built nothing — see the console',
                    SB_PROMPT
                )
                @na_last_status_text = nil
            end

            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Pushpull Inside the Face's Own Editing Context
        # ------------------------------------------------------------
        # THIS is what the whole saga came down to. Editing a definition's
        # entities from OUTSIDE its editing context leaves the model changed but
        # the instance's display cache stale: the push landed, the screen kept
        # showing the old shape until the tool exited — which is why ESC
        # "completed" it, why pushes appeared after a delay, and why picks found
        # real faces where nothing was drawn. invalidate_bounds only refreshes
        # the bounding box, not the render.
        #
        # The create tools never see this because they build into
        # active_entities, the open context, which SketchUp always repaints.
        # So this does what a user does by hand — enter the group, push, leave —
        # via model.active_path= (SketchUp 2020+). The user's own editing
        # context is saved and restored around it.
        #
        # active_path= refuses to run inside an open transaction, so the order
        # is strict: enter context, start_operation, pushpull, commit, restore.
        # KNOWN CAVEAT to verify in testing: programmatic context changes may
        # add their own undo steps around the push.
        # ------------------------------------------------------------
        def na_drawn__execute_push(model, target, local_offset)
            @na_pp_last_error = nil

            # The travel arrives as one vector in the face's REPORTED space and
            # is split here into the part pushpull can do and the part it
            # cannot. Off slope the second part is a zero vector and this is the
            # maths the tool always used. Split BEFORE the context is entered,
            # because the scalar pushpull is given is measured in the
            # definition's own units and this is the last moment the face
            # reports in them.
            split          = Na__InsertPrimatives.Na__SlopePush__SplitOffset(target[:face], local_offset)
            local_distance = split[:distance]
            @na_pp_split   = split                                            # <-- Kept for the console report, which runs after the push

            instances      = Na__InsertPrimatives.Na__DeepPick__Instances(target[:path])
            target_path    = instances.empty? ? nil : instances
            entered        = false
            previous       = nil
            selected       = Na__InsertPrimatives.Na__DeepPick__FocusSnapshot(model)

            if model.respond_to?(:active_path=)
                begin
                    previous = model.active_path                              # <-- nil at root, else the user's context
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

            # THE SPACE FLIPS WHEN THE CONTEXT OPENS. Once its group is entered
            # the face reports global positions and a global normal, geometry
            # added beside it is taken as global and a vertex transform applied
            # to it is read as global (the rule in the DeepPick hub header). So
            # every VECTOR used from here on is re-expressed in that space: the
            # world offset the drag measured, split again against the normal
            # the face now reports. Not entered — the target is in the user's
            # own context, or the open failed — and the local offset already
            # matches what the face reports. Only the pushpull scalar keeps the
            # pre-entry, definition-unit value, because a scalar has no space.
            working_offset = entered ? na_drawn__push_offset_vector : local_offset
            working_split  = entered ? Na__InsertPrimatives.Na__SlopePush__SplitOffset(target[:face], working_offset) : split
            shear          = working_split[:shear]

            pushed  = false
            quads   = na_drawn__quad_mode?
            sheared = shear.length.to_f >= NA_SLOPE_PUSH_MIN_SHEAR
            cut     = Na__InsertPrimatives.Na__EdgeLoops__IsCut?(quads, local_distance)
            op_name = if    cut     then 'Deep Push Pull (Edge Loop)'
                      elsif sheared then 'Deep Push Pull (Slope)'
                      elsif quads   then 'Deep Push Pull (Quads)'
                      else               'Deep Push Pull'
                      end

            # Undo chaining. Entering and leaving the context are undo steps of
            # their own, which is why a push unwound in three Ctrl+Z, with the
            # middle press teleporting the user back inside the group. When a
            # context was entered, the push op is started `transparent` (merging
            # it backwards into the enter step) and `next_transparent` (pulling
            # the restore step forwards into it), so enter-push-restore undoes as
            # ONE action. next_transparent is deprecated and dangerous when a
            # user action can slip in behind it — none can here: the restore runs
            # synchronously below, in this same call, before control returns.
            #
            # The flags are strictly conditional. Without a context change they
            # would merge the push into whatever the user did LAST, making their
            # next Ctrl+Z silently eat two unrelated actions.
            if entered
                model.start_operation(op_name, true, true, true)
            else
                model.start_operation(op_name, true)
            end

            begin
                face   = target[:face]
                parent = face.parent

                # Read the start loops BEFORE the push — pushpull moves the face,
                # and these positions are the only record of where it began.
                loops    = quads ? Na__InsertPrimatives.Na__PushPull__CaptureLoops(face) : []
                entities = parent.respond_to?(:entities) ? parent.entities : model.active_entities

                @na_pp_quad_stats  = nil
                @na_pp_seam_healed = 0
                @na_pp_stretched   = false

                # Read before anything touches the entities: after the push the
                # normal cannot be asked of a face that may no longer be there,
                # and the interior point is what identifies the moved face.
                # Both are in the space the face reports NOW — global if the
                # context was entered — which is the space working_offset is in.
                normal_now = sheared ? face.normal : nil
                interior   = sheared ? Na__InsertPrimatives.Na__SlopePush__InteriorPoint(face) : nil

                if cut
                    # LOOP CUT. Nothing is pushed at all — that is the whole
                    # point of the inward gesture. The ring is offset along the
                    # WHOLE travel, not just its normal share: in slope mode the
                    # faces around this one are the sweep of its loop along the
                    # slope, so that is the direction the cut has to follow to
                    # land in them. Off slope the two are the same vector. The
                    # loops were captured a moment ago in the face's current
                    # space, so the offset must be in that space too.
                    ring_dir  = working_offset.length > 0 ? working_offset.normalize : face.normal
                    ring_step = working_offset.length.to_f
                    inset     = Na__InsertPrimatives.Na__EdgeLoops__OffsetLoops(loops, ring_dir, ring_step)
                    unless inset.empty?
                        build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, inset.first.first)
                        @na_pp_quad_stats = Na__InsertPrimatives.Na__EdgeLoops__Cut(
                            entities, loops, ring_dir, ring_step, build
                        )
                    end
                elsif sheared && interior &&
                      Na__InsertPrimatives.Na__SlopePush__CanStretch?(face, working_offset)
                    # SLOPE, THE CLEAN WAY. Every face touching this one contains
                    # the slope, so the face can simply be carried along it and
                    # they stretch to follow — exactly what selecting the end of
                    # the roof and moving it down the rake does by hand. Nothing
                    # is created, nothing is welded, and there is no seam left
                    # across the surface that was just made continuous.
                    #
                    # A refusal here is raised rather than swallowed. Falling
                    # through to an ordinary push would hand back geometry that
                    # does not match the preview, which is worse than nothing.
                    unless Na__InsertPrimatives.Na__SlopePush__Stretch(entities, face, working_offset)
                        raise 'the face would not move along the slope — no vertex transform took'
                    end

                    @na_pp_stretched = true
                    na_drawn__trace('slope: stretched the face along the neighbour')

                    unless loops.empty?
                        build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, loops.first.first)
                        @na_pp_quad_stats = Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, loops, build)
                    end
                else
                    face.pushpull(local_distance)

                    # SLOPE, THE GENERAL WAY. Something around this face does not
                    # contain the slope, so stretching would pull it out of its
                    # own plane. pushpull takes the normal's share instead and
                    # the sideways remainder is applied to the moved face alone,
                    # which turns every wall the push made from a rectangle into
                    # a parallelogram — still planar, whatever the neighbours are
                    # doing.
                    if sheared
                        # How far the face just travelled, in the space it
                        # reports in: the normal's share of the WORKING split,
                        # which is the pre-entry local distance when nothing was
                        # entered and the global one when the group is open.
                        along  = working_split[:distance].to_f
                        travel = Geom::Vector3d.new(
                            normal_now.x.to_f * along,
                            normal_now.y.to_f * along,
                            normal_now.z.to_f * along
                        )

                        moved = Na__InsertPrimatives.Na__SlopePush__MovedFace(
                            entities, face, interior, travel, normal_now
                        )

                        raise 'the pushed face could not be found again to shear it' unless moved

                        unless Na__InsertPrimatives.Na__SlopePush__ApplyShear(entities, moved, shear)
                            raise 'the pushed face would not shear — no vertex transform took'
                        end

                        face = moved                                          # <-- The seam heal below reads it too
                        na_drawn__trace('slope: pushed and sheared onto the neighbour')
                    end

                    unless loops.empty?
                        build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, loops.first.first)
                        @na_pp_quad_stats = Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, loops, build)
                    end

                    # A normal push welds its new wall into the coplanar one it
                    # grew from and deletes the line between them. A sheared one
                    # cannot — the wall only becomes coplanar once the shear has
                    # run, by which time the weld has already not happened. So
                    # the seam is cleared here instead, and only where it has
                    # genuinely become nothing. QUAD mode exists to KEEP that
                    # line, so this never runs there.
                    if sheared && !quads
                        @na_pp_seam_healed = Na__InsertPrimatives.Na__SlopePush__HealSeam(face)
                    end
                end

                Na__InsertPrimatives.Na__DeepPick__InvalidateDefinitions(target[:path]) unless entered

                # The distance a double-click on the next face will repeat.
                # Written INSIDE the operation so it rides in this undo step
                # rather than costing the user a second Ctrl+Z.
                na_revise__remember(model, na_drawn__signed_d)

                model.commit_operation
                pushed = true
            rescue StandardError => error
                model.abort_operation
                @na_pp_last_error = error.message
                na_drawn__trace("pushpull raised: #{error.message}")
            end

            if entered
                na_drawn__restore_context(model, previous)

                # Opening the group cleared the user's selection, and that
                # selection is what tells the picker which group to favour. Put
                # it back or the focus dies on the first push of the session.
                Na__InsertPrimatives.Na__DeepPick__FocusRestore(model, selected)
            end

            pushed
        end
        # ---------------------------------------------------------------

        # @delegate: ../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Context__.rb (Na__DeepPick__SameContext?)

        # FUNCTION | Put the User Back in the Context They Were In
        # Falls back to the model root rather than ever leaving them stranded
        # inside the group this tool opened.
        # ------------------------------------------------------------
        def na_drawn__restore_context(model, previous)
            model.active_path = previous
        rescue StandardError
            begin
                model.active_path = nil
            rescue StandardError
                nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say Out Loud Why a Push Was Refused
        # ------------------------------------------------------------
        # na_drawn__trace is off by default and a status-bar line is gone by the
        # time anyone thinks to read it, so a refusal that produced NO geometry
        # printed nothing anybody would ever see. That is how slope mode came to
        # be reported as "the preview works and nothing is created", with no way
        # to tell which of four things had gone wrong.
        #
        # A failure is not chatter. It is the one thing always worth printing,
        # and it prints the numbers the next diagnosis needs rather than just
        # the message.
        # ------------------------------------------------------------
        def na_drawn__report_failure(target, local_offset, sloped)
            split = @na_pp_split || { :distance => 0.0, :shear => Geom::Vector3d.new(0, 0, 0) }

            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts 'DEEP PUSH/PULL REFUSED'
            Na__InsertPrimatives.Na__Debug__Puts "Reason: #{@na_pp_last_error}"
            Na__InsertPrimatives.Na__Debug__Puts "Target: #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "Mode  : #{sloped ? 'SLOPE' : 'normal'}#{na_drawn__quad_mode? ? ' + QUADS' : ''}"
            Na__InsertPrimatives.Na__Debug__Puts "Slope : #{sloped ? Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope) : 'n/a'}"
            Na__InsertPrimatives.Na__Debug__Puts "Offset: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(local_offset.length).abs}mm local"
            Na__InsertPrimatives.Na__Debug__Puts "Split : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(split[:distance]).abs}mm along the normal, " \
                 "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(split[:shear].length).abs}mm sideways"
            Na__InsertPrimatives.Na__Debug__Puts "Route : #{@na_pp_stretched ? 'stretch' : 'pushpull + shear'}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA PUSH/PULL: refused, and the report itself failed (#{error.message})"
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Line Saying What the Quad Ring Actually Did
        # Kept edges are the quad lines that survived; swept ones are ring edges
        # that bounded nothing. An inward drag no longer reaches this report at
        # all — it is a loop cut, which keeps its own tally.
        # ------------------------------------------------------------
        def na_drawn__quad_report
            return 'off' unless na_drawn__quad_mode?
            return "LOOP CUT — #{Na__InsertPrimatives.Na__EdgeLoops__Report(@na_pp_quad_stats)}" if na_drawn__loop_cut_mode?

            stats = @na_pp_quad_stats
            return 'ON — no ring built' unless stats

            summary = "ON — #{stats[:kept]} edges kept, #{stats[:swept]} swept, #{stats[:faces_removed]} fill face(s) removed"
            summary << ' — RING LANDED IN THE WRONG SPACE, removed' if stats[:misplaced]
            summary
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Push
        # ------------------------------------------------------------
        def na_drawn__log_push(target, world_travel, sloped)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts(
                na_revise__replaying? ? 'DEEP PUSH/PULL ADJUSTED (retyped distance)' : 'DEEP PUSH/PULL APPLIED'
            )
            Na__InsertPrimatives.Na__Debug__Puts "Target: #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            measured =
                if    @na_axis_lock then " along #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]}"
                elsif sloped        then ' along the neighbouring slope'
                else                     ' along the face normal'
                end

            split = @na_pp_split || { :distance => 0.0, :shear => Geom::Vector3d.new(0, 0, 0) }

            Na__InsertPrimatives.Na__Debug__Puts "Dragged: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm#{measured}"
            Na__InsertPrimatives.Na__Debug__Puts "Travel: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(world_travel).abs}mm world"
            Na__InsertPrimatives.Na__Debug__Puts "Local push   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(split[:distance]).abs}mm (instance scale #{format('%.4f', target[:normal_scale])})"

            if sloped
                route = @na_pp_stretched ? 'stretched (no new geometry, no seam)' : 'pushpull + shear'
                Na__InsertPrimatives.Na__Debug__Puts "Slope        : #{Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope)} — #{route}"
                Na__InsertPrimatives.Na__Debug__Puts "Sideways     : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(split[:shear].length).abs}mm"
                Na__InsertPrimatives.Na__Debug__Puts "Seam         : #{@na_pp_seam_healed.to_i} coplanar edge(s) cleared" unless @na_pp_stretched
            end

            Na__InsertPrimatives.Na__Debug__Puts "Instances affected: #{target[:shared_count]}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts "Quads : #{na_drawn__quad_report}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullCommit module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL COMMIT
# =============================================================================
