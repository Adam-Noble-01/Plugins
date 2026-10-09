# =============================================================================
# NA INSERT PRIMATIVES - DEEP OVOLO TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnOvoloTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnOvoloTool  <  DrawnChamferTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Run an ovolo (convex quarter round) or a cavetto (concave
#              quarter hollow), each with its step, along any edge at any
#              nesting depth
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Chamfer with a different cut, exactly as Deep Ogee and Deep Fillet
#   are: the same hover, SHIFT bank, preselected edges, scrub drag, mitres,
#   retype, double-click repeat and one undo step per group. This class is the
#   moulding's two values, TAB and its words; the curve is in the geometry
#   file, and the profile sweep (DrawnProfileSweepTool) builds and previews it.
#
# TWO VALUES — RADIUS AND STEP:
# - What sets these apart from a plain radius: the quarter circle's radius and
#   the small square step beside it. Typed into the measurements box:
#     40,5    radius 40 and step 5 — cuts
#     40r     radius 40, pinned; the next number is the step: 40r then 5 cuts
#     40      radius 40 at the step already set — cuts
#     ,5      step 5; with the radius already pinned it cuts, otherwise the
#             preview re-solves and the drag carries on
#   The drag (the scrub) sets the radius; the step stays as typed and is
#   remembered between sessions, 5 mm until one is typed. After a cut the same
#   entries re-cut it: 60 resizes the radius, ,2 changes the step, 60,2 both.
#
# TAB — OVOLO OR CAVETTO:
# - TAB swaps the convex ovolo for the concave cavetto, and back: mid-drag on
#   the preview, straight after a cut by re-cutting it, otherwise for the next
#   one. V typed on its own, in any of the edge tools, always gives the ovolo.
#
# THE LIMIT:
# - The faces' reach is measured as a setback. The largest radius is that,
#   less one step for an ovolo or two for a cavetto, less a 1 mm land (see the
#   geometry header). A step too wide for the faces is refused with the
#   widest that fits named, never quietly shrunk.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../31__System__DeepChamfer/Na__InsertPrimatives__DrawnChamferTool__'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__'
require_relative 'Na__InsertPrimatives__DrawnOvolo__Geometry__'
require_relative 'Na__InsertPrimatives__DrawnOvolo__Revise__'

module Na__InsertPrimatives

    # @delegate: Na__InsertPrimatives__DrawnOvolo__Geometry__.rb
    # @delegate: Na__InsertPrimatives__DrawnOvolo__Revise__.rb
    # @delegate: ../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnProfileSweepTool__.rb

    # -----------------------------------------------------------------------------
    # REGION | Deep Ovolo Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Mould an Ovolo or a Cavetto on Any Edge at Any Nesting Depth
    # ------------------------------------------------------------
    class DrawnOvoloTool < DrawnChamferTool

        include Na__InsertPrimatives::DrawnOvoloRevise                        # <-- Over the chamfer's revise half: memory and wording
        include Na__InsertPrimatives::DrawnProfileSweepTool                   # <-- Last, so it sits first: plan, build, mitre, preview, ghost

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            super
            @na_ov_wants_step   = false                                       # <-- "40r" pinned the radius: the next bare number is the step
            @na_ov_max_setback  = nil                                         # <-- The faces' reach, as last measured
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title — Named for the Kind in Hand
        # ------------------------------------------------------------
        def na_drawn__tool_title
            na_ov__cavetto? ? 'Deep Cavetto' : 'Deep Ovolo'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_ovolo
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Hover an edge, click to grab it — the preview opens at 25% of the largest radius the faces allow',
                'Drag UP for a bigger radius, DOWN for a smaller one, then click to cut',
                'SHIFT+click banks edges, then one drag moulds them all — square corners mitre',
                'Reaches edges inside groups and components without opening them',
                "Radius snaps to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid — hold CTRL for vertex snapping",
                "VCB: 40,5 radius and step | 40r then 5 | 40 keeps the step (now #{na_ov__mm_text(na_drawn__ovolo_step)}) | ,5 sets the step",
                'TAB swaps ovolo (convex quarter round) and cavetto (concave quarter hollow)',
                "48s smooths the arc (now #{Na__InsertPrimatives.Na__DrawnSettings__CircleSegments} circle sides)",
                'After cutting, keep typing: 60 re-cuts at R60, ,2 re-steps it, 60,2 does both',
                'Double-click an edge to mould it at the last radius placed (remembered in the model)',
                'Type C chamfer, R radius, O ogee, V ovolo on their own to swap the profile, keeping the edges',
                'The edge must border exactly two faces'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cut Hooks — the Ovolo's Words and Curve
        # -----------------------------------------------------------------------------

        # FUNCTION | What the Cut Is Called, for Messages and Undo Names
        # ------------------------------------------------------------
        def na_drawn__cut_title
            na_ov__cavetto? ? 'Cavetto' : 'Ovolo'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut With Its Article, for Messages
        # ------------------------------------------------------------
        def na_drawn__cut_phrase
            na_ov__cavetto? ? 'a cavetto' : 'an ovolo'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Cut as a Verb, for Messages
        # ------------------------------------------------------------
        def na_drawn__cut_verb
            'mould'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Solve One Edge at a World Radius, Beside the Step in Hand
        # Plan, build and mitre come from DrawnProfileSweepTool.
        # ------------------------------------------------------------
        def na_drawn__solve_cut(target, radius)
            Na__InsertPrimatives.Na__DrawnOvolo__Solve(
                target, radius, na_drawn__ovolo_step, na_drawn__ovolo_kind, na_drawn__ovolo_arc_segments
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read a CTRL Vertex Snap as a Radius
        # The plain drag is the scrub; only CTRL's absolute vertex snap reads
        # travel along the bisector. The arc passes through the snapped point.
        # ------------------------------------------------------------
        def na_drawn__size_from_travel(travel)
            Na__InsertPrimatives.Na__DrawnOvolo__RadiusFromTravel(
                travel, @na_ch_cos_half, na_drawn__ovolo_step, na_drawn__ovolo_kind
            )
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Profile Settings
        # -----------------------------------------------------------------------------

        # FUNCTION | Ovolo or Cavetto
        # A rebuild answers with the kind the moulding it is rebuilding was cut
        # as, so a retype never quietly swaps it because TAB was pressed in
        # between. Only TAB's own re-cut asks for the other kind, on purpose.
        # ------------------------------------------------------------
        def na_drawn__ovolo_kind
            replaying = @na_revise_replaying
            return (replaying[:kind] == :cavetto ? :cavetto : :ovolo) if replaying && replaying.key?(:kind)

            Na__InsertPrimatives.Na__DrawnSettings__OvoloCavetto? ? :cavetto : :ovolo
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Moulding in Hand a Cavetto?
        # ------------------------------------------------------------
        def na_ov__cavetto?
            na_drawn__ovolo_kind == :cavetto
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Step, in Internal Inches
        # A rebuild wears the step its record was cut with; anything else wears
        # the remembered setting, which a typed step updates.
        # ------------------------------------------------------------
        def na_drawn__ovolo_step
            replaying = @na_revise_replaying
            return replaying[:step].to_f if replaying && replaying.key?(:step)

            Na__InsertPrimatives.Na__DrawnSettings__OvoloStepMm.to_f / NA_DRAWN_INCH_TO_MM
        end
        # ---------------------------------------------------------------

        # FUNCTION | Facets per Quarter Arc, From the Circle Sides Setting
        # ------------------------------------------------------------
        def na_drawn__ovolo_arc_segments
            sides = Na__InsertPrimatives.Na__DrawnSettings__CircleSegments.to_f
            [(sides / 4.0).round, NA_OVOLO_MIN_ARC_SEGMENTS].max
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Shapes the Moulding Besides Its Radius
        # Merged into the retype record by the shared capture, and compared to
        # tell when the replay ghost is a different shape.
        # ------------------------------------------------------------
        def na_drawn__profile_state
            {
                :kind  => na_drawn__ovolo_kind,
                :step  => na_drawn__ovolo_step,
                :sides => Na__InsertPrimatives.Na__DrawnSettings__CircleSegments
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | How a Radius Reads in Labels
        # ------------------------------------------------------------
        def na_drawn__size_text(value)
            "R#{Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write a Step Into the Remembered Setting
        # Rounded to a thousandth of a millimetre, so a typed 8 is stored as 8
        # and not as the 7.999999 the round trip through inches can leave.
        # ------------------------------------------------------------
        def na_ov__store_step(step)
            Na__InsertPrimatives.Na__DrawnSettings__SetOvoloStepMm((step.to_f * NA_DRAWN_INCH_TO_MM).round(3))
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Limit — a Setback, Less the Step
        # -----------------------------------------------------------------------------

        # FUNCTION | The Largest Radius Every Edge of a Batch Can Take, or nil
        # Over DrawnChamferLimit's: the reach is measured once as a setback and
        # the step taken off it, because the step does not grow with the
        # radius. Zero or less when the step alone does not fit. The setback is
        # kept, so a retype that changes the step can be judged without the
        # faces (they are gone once the moulding is cut).
        # ------------------------------------------------------------
        def na_lm__max_for(targets)
            setbacks = (targets || []).compact.map { |target| Na__InsertPrimatives.Na__DrawnOvolo__MaxSetback(target) }.compact
            @na_ov_max_setback = setbacks.min
            return nil if @na_ov_max_setback.nil?

            Na__InsertPrimatives.Na__DrawnOvolo__MaxRadius(@na_ov_max_setback, na_drawn__ovolo_step, na_drawn__ovolo_kind)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Refusal Wording That Names the Limit — and the Step
        # ------------------------------------------------------------
        def na_lm__over_message(size, max)
            step = na_ov__mm_text(na_drawn__ovolo_step)
            return na_ov__no_room_message if max.to_f <= 0.0

            "#{na_drawn__size_text(size)} with a #{step} step is more than this corner has — " \
            "the faces allow #{na_drawn__size_text(max)} at most with that step"
        end
        # ---------------------------------------------------------------

        # FUNCTION | " · 75% of R53 max", or Why There Is No Room
        # ------------------------------------------------------------
        def na_lm__range_note(size, max)
            return '' if max.nil?
            return ' · no room at this step' unless max.to_f > 0.0

            percent = ((size.to_f / max.to_f) * 100.0).round
            percent = 100 if percent > 100
            " · #{percent}% of #{na_drawn__size_text(max)} max"
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Step Is Too Wide for These Faces — Say the Widest That Fits
        # ------------------------------------------------------------
        def na_ov__no_room_message
            step  = na_ov__mm_text(na_drawn__ovolo_step)
            widest = Na__InsertPrimatives.Na__DrawnOvolo__MaxStep(@na_ov_max_setback, na_drawn__ovolo_kind)

            if widest && widest > 0.0
                "a #{step} step leaves no room for #{na_drawn__cut_phrase} on these faces — " \
                "type a step under #{na_ov__mm_text(widest)}, e.g. ,#{[(widest * NA_DRAWN_INCH_TO_MM * 0.5).floor, 1].max}"
            else
                "these faces are too narrow for #{na_drawn__cut_phrase} with any step — try ,0 or another edge"
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check a Radius and Step Against a Measured Setback
        # Raises ArgumentError naming the fix; never shrinks anything to fit.
        # ------------------------------------------------------------
        def na_ov__check_fit(radius, step, kind, max_setback)
            unless radius.to_f > NA_DRAWN_MIN_DIMENSION.to_f
                raise ArgumentError, "radius would be #{Na__InsertPrimatives.Na__DrawnFormat__Mm(radius)}mm — it must be more than nothing"
            end

            raise ArgumentError, "a step can't be less than nothing — ,0 is no step at all" if step.to_f < 0.0
            return true if max_setback.nil?

            most = Na__InsertPrimatives.Na__DrawnOvolo__MaxRadius(max_setback, step, kind)
            phrase = kind == :cavetto ? 'a cavetto' : 'an ovolo'

            unless most > 0.0
                widest = Na__InsertPrimatives.Na__DrawnOvolo__MaxStep(max_setback, kind)
                raise ArgumentError, "a #{na_ov__mm_text(step)} step leaves no room for #{phrase} here — the step must be under #{na_ov__mm_text(widest)}"
            end

            if radius.to_f > most + NA_CHAMFER_LIMIT_TOL
                raise ArgumentError,
                      "#{na_drawn__size_text(radius)} with a #{na_ov__mm_text(step)} step needs " \
                      "#{na_ov__mm_text(Na__InsertPrimatives.Na__DrawnOvolo__Setback(radius, step, kind))} on each face — " \
                      "this corner allows #{na_drawn__size_text(most)} at most with that step"
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measure Again After the Kind or the Step Changed Mid-Drag
        # A dragged radius over the new limit comes down to it; a typed one is
        # left for the commit to refuse by name. A preview with nothing to show
        # because the old step did not fit opens at 25% of the new limit.
        # ------------------------------------------------------------
        def na_ov__remeasure(view)
            return false unless @na_state == :picking_depth && @na_ch_target

            batch           = @na_ch_batch.empty? ? [@na_ch_target] : @na_ch_batch
            @na_ch_max_size = na_lm__max_for(batch)
            max             = @na_ch_max_size
            locked          = na_drawn__locked?(:d)

            if max && !locked
                if max.to_f <= 0.0
                    @na_size_d = 0.0
                elsif @na_size_d.to_f > max.to_f
                    @na_size_d = max.to_f
                elsif @na_size_d.to_f <= 0.0
                    @na_size_d = na_sc__opening_size(view)
                end
            end

            na_sc__rebase(@na_last_mouse_y, @na_size_d)
            na_drawn__refresh_solve
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Record Keeps the Setback, So a New Step Can Be Judged
        # ------------------------------------------------------------
        def na_revise__capture(members, solves, ops)
            super

            @na_revise_record[:max_setback] = @na_ov_max_setback if @na_revise_record && @na_ov_max_setback
            @na_ov_wants_step = false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Retype — Radius, Step, or Both
        # -----------------------------------------------------------------------------

        # FUNCTION | A Typed Entry After a Cut Re-Cuts It
        # "60" resizes the radius, ",2" changes the step, "60,2" both, "+5" adds
        # to the radius. The new pair is checked against the setback the cut
        # was measured with before anything is undone; a new step is written
        # into a copy of the record, which the rebuild wears, and remembered
        # for the next moulding. "48s" goes the shared way (a smoother arc at
        # the same size).
        # ------------------------------------------------------------
        def na_revise__retype(text, view)
            record = @na_revise_record
            return super if record.nil? || Na__InsertPrimatives.Na__DrawnVcb__SegmentEntry(text)

            entry  = Na__InsertPrimatives.Na__DrawnOvolo__ParseEntry(text)
            radius = entry[:radius] ? Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(entry[:radius], record[:value]) : record[:value].to_f.abs
            step   = entry[:step]   ? Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(entry[:step], record[:step]) : record[:step].to_f
            kind   = record[:kind] == :cavetto ? :cavetto : :ovolo

            na_ov__check_fit(radius, step, kind, record[:max_setback])

            wearing = record
            if entry[:step]
                na_ov__store_step(step)
                wearing = record.merge(:step => step)
            end

            na_revise__rebuild_at(wearing, radius, view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | TAB and V — Ovolo or Cavetto
        # -----------------------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            'TAB ovolo/cavetto'
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Swaps Ovolo and Cavetto — Live, or on the One Just Cut
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            cavetto = Na__InsertPrimatives.Na__DrawnSettings__SetOvoloCavetto(!Na__InsertPrimatives.Na__DrawnSettings__OvoloCavetto?)
            na_ov__apply_kind(view, cavetto)
        end
        # ---------------------------------------------------------------

        # FUNCTION | V Typed While Deep Ovolo Runs: Back to the Ovolo
        # ------------------------------------------------------------
        def na_hs__same_profile_letter(profile)
            return super unless profile == :ovolo && Na__InsertPrimatives.Na__DrawnSettings__OvoloCavetto?

            Na__InsertPrimatives.Na__DrawnSettings__SetOvoloCavetto(false)
            model = Sketchup.active_model
            na_ov__apply_kind(model ? model.active_view : nil, false)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Show the Kind Just Chosen — Mid-Drag, on the Last Cut, or Next Time
        # The setting has already changed. Mid-drag the limit is measured again
        # (a cavetto takes two steps of the face, an ovolo one) and the preview
        # re-solves; straight after a cut the moulding just made is re-cut as
        # the other kind through the same undo-and-rebuild a typed radius uses.
        # ------------------------------------------------------------
        def na_ov__apply_kind(view, cavetto)
            name    = cavetto ? 'a cavetto — the concave quarter hollow' : 'an ovolo — the convex quarter round'
            message = nil

            if @na_state == :picking_depth
                na_ov__remeasure(view)
                message = "Now #{name}"
            elsif na_revise__available?
                record  = @na_revise_record
                recut   = na_revise__rebuild_at(record.merge(:kind => cavetto ? :cavetto : :ovolo), record[:value], view)
                message = "Re-cut as #{cavetto ? 'a cavetto' : 'an ovolo'}" if recut
            else
                message = "The next moulding will be #{name}"
            end

            na_revise__notice(message) if message
            @na_last_status_text = nil
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | State Around a Pinned Radius
        # -----------------------------------------------------------------------------

        # FUNCTION | Forget the Grabbed Edge — and Any Radius Waiting for Its Step
        # ------------------------------------------------------------
        def na_drawn__clear_target
            super
            @na_ov_wants_step = false
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP Releasing the Radius Stops Waiting for a Step
        # ------------------------------------------------------------
        def na_drawn__release_last_lock
            released = super
            @na_ov_wants_step = false if released && !na_drawn__locked?(:d)
            released
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Moulding and Its Summary Card
        # With no room at the step in hand there is nothing to draw, so the
        # edge stays lit and the card says why, and what to type.
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            solve = @na_ch_solve

            if solve.nil? && @na_ch_max_size && @na_ch_max_size.to_f <= 0.0 &&
               @na_ch_target && @na_ch_target[:edge] && @na_ch_target[:edge].valid?
                na_drawn__draw_edge_highlight(view)
                xform = @na_ch_target[:transformation]
                Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                    view, @na_ch_target[:edge].start.position.transform(xform),
                    ["#{na_drawn__cut_title}: #{na_ov__no_room_message}"], 14, 18, NA_DRAWN_REFUSED_TEXT_COLOR
                )
                return
            end

            lines = []

            if solve
                other   = solve[:kind] == :cavetto ? 'ovolo' : 'cavetto'
                back    = na_ov__mm_text(solve[:setback_world])
                edge_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs
                lines << "#{na_drawn__cut_title} #{na_drawn__size_text(@na_size_d)} · #{na_ov__mm_text(na_drawn__ovolo_step)} step" \
                         "#{na_lm__range_note(@na_size_d, @na_ch_max_size)}"
                lines << "#{back} back on each face · #{solve[:facets]} facets · TAB #{other} · edge #{edge_mm} mm"
                lines << 'now type the step (e.g. 5), or click to cut' if @na_ov_wants_step
            end

            na_drawn__draw_profile_preview(view, lines)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            step = na_ov__mm_text(na_drawn__ovolo_step)

            if @na_state == :picking_depth
                return "#{na_drawn__cut_title}: #{na_ov__no_room_message}" if @na_ch_max_size && @na_ch_max_size.to_f <= 0.0

                size = na_drawn__size_text(@na_size_d)
                text = na_drawn__locked?(:d) ? "[#{size}]" : size
                return "#{na_drawn__cut_title} #{text} + #{step} step — CORNER PROBLEM: #{@na_ch_mitre_note}" if @na_ch_mitre_note
                return "#{na_drawn__cut_title} #{text} pinned — type the step (e.g. 5), or click to cut at #{step}" if @na_ov_wants_step

                return "#{na_drawn__cut_title} #{text} + #{step} step#{na_lm__range_note(@na_size_d, @na_ch_max_size)}#{na_drawn__stop_note}" \
                       ' — drag up for more, down for less, release or click to cut'
            end

            return na_ps__status_detail if na_ps__active?                        # <-- Preselected edges, from the chamfer

            adjust = na_revise__status_hint

            if @na_ch_target
                return 'Edge borders more than two faces — pick another' unless @na_ch_target[:face_count] == 2
                return "Click to grab this edge#{na_drawn__focus_hint}#{adjust}"
            end

            if @na_ch_multi.any?
                return "#{@na_ch_multi.length} edge#{@na_ch_multi.length == 1 ? '' : 's'} banked — SHIFT+click adds, click one to mould them all#{adjust}"
            end

            "Hover an edge to mould #{na_drawn__cut_phrase} (#{step} step — 40,5 sets radius and step), at any nesting depth#{na_drawn__focus_hint}#{adjust}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value — Radius, Step
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            label = "#{na_drawn__cut_title} radius,step"
            step  = na_ov__mm_number(na_drawn__ovolo_step)

            if @na_state != :picking_depth
                if na_revise__available?
                    record = @na_revise_record
                    return [label, "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(record[:value]).abs},#{na_ov__mm_number(record[:step])}"]
                end

                return [label, "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_revise_memory).abs},#{step}"] if na_revise__memory?

                return [label, ",#{step}"]
            end

            [label, "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs},#{step}"]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | Radius, Step, Both — or "48s" for a Smoother Arc
        # ------------------------------------------------------------
        # Mid-drag:
        #   40,5    sets both and cuts
        #   40      sets the radius and cuts, at the step in hand
        #   40r     pins the radius and waits: the next bare number is the step
        #   ,5      sets the step; cuts if the radius is pinned, otherwise the
        #           preview re-solves and the drag carries on
        # Idle, ",5" sets the step for the next moulding. After a cut, any of
        # them re-cuts it (the retype above). A typed step that leaves no room
        # on these faces is refused with the widest that fits named.
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            segments = Na__InsertPrimatives.Na__DrawnVcb__SegmentEntry(text)
            if segments
                return na_revise__retype(text, view) if na_revise__available?

                count = Na__InsertPrimatives.Na__DrawnSettings__SetCircleSegments(segments)
                na_drawn__refresh_solve if @na_state == :picking_depth
                na_revise__notice("#{na_drawn__cut_title} arc: #{count} circle sides — #{na_drawn__ovolo_arc_segments} facets on the quarter round")
                view.invalidate if view
                return true
            end

            return na_revise__retype(text, view) if na_revise__available?

            entry = Na__InsertPrimatives.Na__DrawnOvolo__ParseEntry(text)

            unless @na_state == :picking_depth
                if entry[:radius].nil? && entry[:step]
                    step = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(entry[:step], na_drawn__ovolo_step)
                    raise ArgumentError, "a step can't be less than nothing — ,0 is no step at all" if step < 0.0

                    na_ov__store_step(step)
                    na_revise__notice("#{na_ov__mm_text(step)} step for the next #{na_revise__noun}")
                    return true
                end

                UI.beep
                Sketchup::set_status_text("Grab an edge before typing a radius — ,5 on its own sets the step#{na_revise__status_hint}", SB_PROMPT)
                return false
            end

            # "40r" pinned the radius, so a bare number now is the step.
            if @na_ov_wants_step && entry[:radius] && entry[:step].nil? && !entry[:marked]
                entry = { :radius => nil, :step => entry[:radius], :marked => false }
            end

            stepped = false
            if entry[:step]
                step = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(entry[:step], na_drawn__ovolo_step)
                raise ArgumentError, "a step can't be less than nothing — ,0 is no step at all" if step < 0.0

                if @na_ov_max_setback && Na__InsertPrimatives.Na__DrawnOvolo__MaxRadius(@na_ov_max_setback, step, na_drawn__ovolo_kind) <= 0.0
                    widest = Na__InsertPrimatives.Na__DrawnOvolo__MaxStep(@na_ov_max_setback, na_drawn__ovolo_kind)
                    raise ArgumentError, "a #{na_ov__mm_text(step)} step leaves no room for #{na_drawn__cut_phrase} here — the step must be under #{na_ov__mm_text(widest)}"
                end

                na_ov__store_step(step)
                stepped = true
            end

            if entry[:radius]
                radius = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(entry[:radius], @na_size_d)
                Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive([radius], ['Radius'])

                if entry[:marked]
                    na_ov__check_fit(radius, na_drawn__ovolo_step, na_drawn__ovolo_kind, @na_ov_max_setback)   # <-- Pinned and waiting: refused now, not at the click
                end

                @na_size_d = radius
                na_drawn__lock_slot(:d)
            end

            na_ov__remeasure(view)

            if entry[:marked]
                @na_ov_wants_step = true
                na_revise__notice("#{na_drawn__size_text(@na_size_d)} pinned — now type the step (e.g. 5), or click to cut at #{na_ov__mm_text(na_drawn__ovolo_step)}")
                view.invalidate if view
                return true
            end

            cut_now = entry[:radius] || (stepped && na_drawn__locked?(:d))

            unless cut_now
                na_revise__notice("#{na_ov__mm_text(na_drawn__ovolo_step)} step — drag for the radius, or type it")
                view.invalidate if view
                return true
            end

            @na_ov_wants_step = false
            na_drawn__commit_chamfer(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Ghost and Console
        # -----------------------------------------------------------------------------

        # FUNCTION | Scale the Retype Ghost by the Whole Setback
        # The step does not grow with the radius, so the ratio of the two radii
        # would swell the step too; the ratio of the two setbacks keeps the
        # ghost's outer edge where the new moulding's will be.
        # ------------------------------------------------------------
        def na_revise__ghost_scale(ghost, value)
            state = ghost[:state] || {}
            kind  = state[:kind] == :cavetto ? :cavetto : :ovolo
            step  = state[:step].to_f
            from  = Na__InsertPrimatives.Na__DrawnOvolo__Setback(ghost[:from_setback].to_f, step, kind)
            to    = Na__InsertPrimatives.Na__DrawnOvolo__Setback(value.to_f.abs, step, kind)

            from > 0.0 ? to / from : 1.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Ovolo or Cavetto
        # The chamfer tool calls this after a single-edge cut.
        # ------------------------------------------------------------
        def na_drawn__log_chamfer(target, solve)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts "DEEP #{na_drawn__cut_title.upcase} CUT"
            Na__InsertPrimatives.Na__Debug__Puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "Radius : #{na_drawn__size_text(@na_size_d)} with a #{na_ov__mm_text(solve[:step_world])} step, #{solve[:facets]} facets"
            Na__InsertPrimatives.Na__Debug__Puts "Setback: #{na_ov__mm_text(solve[:setback_world])} back on each face"
            Na__InsertPrimatives.Na__Debug__Puts "Edge   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(solve[:edge_len_world]).abs}mm long"
            Na__InsertPrimatives.Na__Debug__Puts "Instances affected: #{target[:shared_count]}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid   : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnOvoloTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Deep Ovolo Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Extensions menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DeepOvolo
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepOvolo
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnOvoloTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP OVOLO TOOL MODULE
# =============================================================================
