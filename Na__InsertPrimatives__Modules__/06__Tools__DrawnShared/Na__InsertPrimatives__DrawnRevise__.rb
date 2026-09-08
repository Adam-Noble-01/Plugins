# =============================================================================
# NA INSERT PRIMATIVES - DRAWN REVISE (SHARED BY EVERY MODIFIER TOOL)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnRevise__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnReviseShared
# AUTHOR     : Noble Architecture
# PURPOSE    : Retype, repeat and re-animate the last placed modifier operation
# CREATED    : 2026
#
# DESCRIPTION:
# - Native Push/Pull leaves the measurements box live after the click that
#   places an extrusion: type 1200, Enter, and the push you just made becomes
#   1200 — again and again until you start something else. Double-clicking
#   another face repeats the last distance without a drag. Fredo's Joint
#   Push/Pull does both. Every SketchUp user has both in their hands, and a
#   modifier tool without them is one slip of the finger away from "there is
#   no way to correct that".
# - This mixin is those two habits, built once and shared by Deep Push/Pull
#   (3D and 2D) and Deep Chamfer. It owns everything that is the same across
#   the three: the record of the last placement, the watch on the undo stack,
#   the retype flow, the double-click repeat and the remembered value. What
#   differs — how a target is found again after an undo, how the commit is
#   run, how the ghost is drawn — is the small host contract below.
#
# HOW A RETYPE WORKS (undo, rebuild, animate):
# - Topping the geometry up by the difference is the obvious cheap version
#   and it falls apart on the first quad ring, slope shear or sign flip. So
#   the placement is taken back off the undo stack with Sketchup.undo and the
#   commit path is RUN AGAIN at the new size. Typing 1200 is byte-for-byte
#   what dragging 1200 would have been, in every mode, because there is only
#   one implementation of what the operation is. Repeat entries cost one undo
#   step in total, which is what native does too.
#
# HOW IT KNOWS THE UNDO STACK IS STILL OURS:
# - Sketchup.undo pops whatever is on top. Call it when the top is someone
#   else's work and it destroys that work. The 5.1.0 version guessed at this
#   by counting entities and probing for faces, could not be made to work for
#   a loop cut at all, and refused in cases it did not need to.
# - This version is TOLD instead. A Sketchup::ModelObserver (DrawnReviseWatch)
#   rides on the model while the tool is active; any transaction that lands
#   after ours — a commit, an undo, a redo, from any source — closes the
#   record. The tool's own onCancel(2), which SketchUp raises on a user undo,
#   is the second witness. A cheap entity-count sanity check stays as a
#   third, run once at the moment a size is typed, before anything is undone.
# - While OUR undo-and-rebuild runs the watch is told to look away, so the
#   record being rebuilt is not closed by its own footsteps.
# - Nothing else closes it. Moving the mouse, hovering other faces, pressing
#   TAB or an arrow, opening the right-click menu: the retype stays open
#   through all of it. Only grabbing a new target, changing the model, or
#   leaving the tool ends it — the same three things that end it natively.
#
# THE REMEMBERED VALUE (double-click repeat):
# - Every successful placement writes its measured value into the model's own
#   attribute dictionary (Na__InsertPrimatives__ToolMemory) from INSIDE the
#   placing operation, so it rides in the same undo step. The tool reads it
#   back on activation, so it survives switching tools, reloading the plugin
#   and reopening the file.
# - A double-click on a fresh target with no drag behind it applies that
#   value, exactly as native Push/Pull repeats its last distance. A
#   double-click that lands within half a second of a placement is read as
#   "place, then grab the next face" rather than "repeat", because that is
#   what two quick clicks in a row on a busy model almost always are.
#
# HOST CONTRACT — a tool including this mixin (AFTER DrawnToolShared) defines:
#   na_revise__memory_key                 String key in the tool memory dictionary
#   na_revise__noun                       'push' / 'pull' / 'chamfer', for messages
#   na_revise__target_noun                'a face' / 'an edge', for messages
#   na_revise__sign_hint                  What a leading sign means when retyping
#   na_revise__parse_retype(text, rec)    Text -> the value to rebuild at (raises ArgumentError)
#   na_revise__reacquire(record)          After the undo: the target(s) again, or nil
#   na_revise__rebuild(rec, tgt, v, view) Run the commit path at v; true on success
#   na_revise__apply_repeat(v, view)      Commit the grabbed target at the remembered value
#   na_revise__draw_ghost(view, ghost, value, from, to)   One animation frame
#   na_revise__ghost_points(ghost, value)                 Points for the draw extents
#   na_revise__placed_label(record)       Optional; how the placed size reads in the status bar
#
# RECORD SHAPE (built by the host's capture, armed with na_revise__arm):
#   :value      the signed measured size the placement was made at
#   :ops        how many undo steps the placement took (1 unless a batch)
#   :counts     [[entities, count], ...] the sanity check reads
#   :user_path  the editing context the user was in, restored after the undo
#   :ghost      what the animation draws — host-specific
#   ...plus whatever the host needs to rebuild
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnRevise__Watch__'
require_relative 'Na__InsertPrimatives__DrawnRevise__Animate__'
require_relative '../02__AppData/Na__InsertPrimatives__AppData__ToolMemory__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__Context__'

module Na__InsertPrimatives

    module DrawnReviseShared

        include Na__InsertPrimatives::DrawnReviseAnimate

        # -----------------------------------------------------------------------------
        # REGION | Constants
        # -----------------------------------------------------------------------------

        NA_REVISE_REPEAT_GUARD_S = 0.55                                       # <-- A double-click this soon after a placement is place-then-grab
        NA_REVISE_NOTICE_DELAY_S = 0.1                                        # <-- Same beat the measurements box is re-armed on

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | State
        # -----------------------------------------------------------------------------

        # FUNCTION | Create Every Instance Variable the Mixin Relies On
        # ------------------------------------------------------------
        def na_revise__init_state
            @na_revise_record        = nil                                    # <-- Everything the last placement was made from
            @na_revise_replaying     = nil                                    # <-- The record being rebuilt, while a rebuild runs
            @na_revise_busy          = false                                  # <-- Our own undo / rebuild is in flight
            @na_revise_watch         = nil
            @na_revise_watched_model = nil
            @na_revise_placed_at     = nil                                    # <-- Time of the last placement; the double-click guard
            @na_revise_memory        = nil                                    # <-- Remembered value, internal inches, signed
            na_revise__init_animation
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | SketchUp Tool API — Life Cycle Wrappers
        # -----------------------------------------------------------------------------

        # ACTIVATE | Start Watching the Undo Stack and Read the Remembered Value
        # ------------------------------------------------------------
        def activate
            super
            na_revise__attach_watch
            na_revise__load_memory
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Leaving the Tool Ends the Retype
        # ------------------------------------------------------------
        def deactivate(view)
            na_revise__stop_animation
            na_revise__detach_watch
            na_revise__forget
            super
        end
        # ---------------------------------------------------------------

        # ON CANCEL | Reason 2 Is a User Undo — the Second Witness
        # ------------------------------------------------------------
        def onCancel(reason, view)
            na_revise__on_transaction(:undo) if reason == 2
            super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Record Lifetime
        # -----------------------------------------------------------------------------

        # FUNCTION | Is There a Placement Still Waiting to Be Retyped?
        # Cheap on purpose: the status line and the measurements box ask this on
        # every mouse move. The expensive questions are asked once, at the
        # moment a size is actually typed.
        # ------------------------------------------------------------
        def na_revise__available?
            return false unless @na_state == :idle
            return false unless @na_revise_record

            na_revise__record_live?(@na_revise_record)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arm the Retype With a Fresh Record
        # ------------------------------------------------------------
        def na_revise__arm(record)
            @na_revise_record    = record
            @na_revise_placed_at = Time.now
            record
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drop the Chance to Retype the Last Placement
        # @na_revise_replaying is deliberately left alone: it says a rebuild is
        # RUNNING, it is owned by the host's wearing block, and a commit that
        # fails part way through one must not clear it out from under it.
        # ------------------------------------------------------------
        def na_revise__forget
            @na_revise_record = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Rebuild Running Right Now?
        # ------------------------------------------------------------
        def na_revise__replaying?
            !@na_revise_replaying.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Are the Collections the Record Points At Still Alive?
        # Sketchup::Entities is a COLLECTION, not an Entity, so it has no valid?
        # to ask — touching a purged one raises instead, so it is asked its
        # length and the raise is the answer.
        # ------------------------------------------------------------
        def na_revise__record_live?(record)
            counts = record[:counts]
            return true unless counts.is_a?(Array)

            counts.all? { |entities, _count| !na_revise__entity_count(entities).nil? }
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Many Entities a Collection Holds, or nil If It Is Gone
        # ------------------------------------------------------------
        def na_revise__entity_count(entities)
            return nil unless entities

            entities.length.to_i
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Do the Recorded Collections Still Hold What They Held?
        # The third witness. Cheap, run once before the undo, and it catches a
        # model change the observer somehow never saw.
        # ------------------------------------------------------------
        def na_revise__still_current?(record)
            counts = record[:counts]
            return true unless counts.is_a?(Array)

            counts.all? do |entities, count|
                counted = na_revise__entity_count(entities)
                !counted.nil? && !count.nil? && counted == count.to_i
            end
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Undo Stack Watch
        # -----------------------------------------------------------------------------

        # FUNCTION | Ride the Model While the Tool Is Active
        # ------------------------------------------------------------
        def na_revise__attach_watch
            model = Sketchup.active_model
            return false unless model

            na_revise__detach_watch
            @na_revise_watch ||= Na__InsertPrimatives::DrawnReviseWatch.new(self)
            model.add_observer(@na_revise_watch)
            @na_revise_watched_model = model
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA REVISE: could not watch the model — #{error.message}"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stop Riding the Model
        # ------------------------------------------------------------
        def na_revise__detach_watch
            model = @na_revise_watched_model
            @na_revise_watched_model = nil
            return false unless model && @na_revise_watch

            model.remove_observer(@na_revise_watch)
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Transaction Landed — Is It Ours?
        # Called by the watch and by onCancel(2). Ours while busy; anything
        # else means the placement is no longer the top of the stack and the
        # record is closed without touching the model.
        # ------------------------------------------------------------
        def na_revise__on_transaction(kind)
            return false if @na_revise_busy
            return false unless @na_revise_record

            na_revise__forget
            @na_last_status_text = nil                                        # <-- Let the composed line lose its retype hint
            Na__InsertPrimatives.Na__Debug__Puts "NA REVISE: the placed #{na_revise__noun} is no longer the last thing done (#{kind}) — retype closed"
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Remembered Value (Model Dictionary)
        # -----------------------------------------------------------------------------

        # FUNCTION | Read the Tool's Last Value Back Out of the Model
        # ------------------------------------------------------------
        def na_revise__load_memory
            model = Sketchup.active_model
            @na_revise_memory = model ? Na__InsertPrimatives.Na__ToolMemory__Read(model, na_revise__memory_key) : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remember a Placed Value — Inside the Open Operation Only
        # ------------------------------------------------------------
        def na_revise__remember(model, value)
            return false unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(value)

            @na_revise_memory = value.to_f
            Na__InsertPrimatives.Na__ToolMemory__Write(model, na_revise__memory_key, value)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is There a Value to Repeat?
        # ------------------------------------------------------------
        def na_revise__memory?
            !@na_revise_memory.nil? &&
                Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_revise_memory)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Double-Click Repeat
        # -----------------------------------------------------------------------------

        # FUNCTION | Is This Double-Click a Repeat, or Place-Then-Grab?
        # ------------------------------------------------------------
        def na_revise__repeat_allowed?
            return false unless na_revise__memory?
            return true if @na_revise_placed_at.nil?

            (Time.now - @na_revise_placed_at).to_f > NA_REVISE_REPEAT_GUARD_S
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply the Remembered Value to the Grabbed Target, or Say Why Not
        # Too soon after a placement is not an error: the grab is left live and
        # the user carries on dragging, which is what they were doing.
        # ------------------------------------------------------------
        def na_revise__repeat_or_refuse(view)
            unless na_revise__memory?
                UI.beep
                Sketchup::set_status_text(
                    "Nothing to repeat yet — drag or type a #{na_revise__noun} size first",
                    SB_PROMPT
                )
                return false
            end

            return false unless na_revise__repeat_allowed?

            na_revise__apply_repeat(@na_revise_memory, view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Retype Itself
        # -----------------------------------------------------------------------------

        # FUNCTION | A Size Typed While Idle Rebuilds the Last Placement
        # The host parses the text, because the two tools read a leading sign
        # differently — see each tool's na_revise__parse_retype.
        # ------------------------------------------------------------
        def na_revise__retype(text, view)
            record = @na_revise_record

            unless record
                UI.beep
                Sketchup::set_status_text("Nothing placed to adjust — grab #{na_revise__target_noun} first", SB_PROMPT)
                return false
            end

            value = na_revise__parse_retype(text, record)
            na_revise__rebuild_at(record, value, view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take the Placement Back Off the Stack and Make It Again
        # The record is left exactly as it was until a rebuild has landed,
        # because it is also the recipe for putting the user's own placement
        # back if the new size turns out to be one the geometry will not take.
        # An undo with nothing rebuilt after it is the one outcome this must
        # never leave behind.
        # ------------------------------------------------------------
        def na_revise__rebuild_at(record, value, view)
            model = Sketchup.active_model
            return false unless record && model

            unless na_revise__still_current?(record)
                UI.beep
                na_revise__notice("That #{na_revise__noun} is no longer the last thing done — nothing adjusted")
                Na__InsertPrimatives.Na__Debug__Puts "NA REVISE: retype refused — the recorded #{na_revise__noun} is not what is standing there"
                na_revise__forget
                return false
            end

            @na_revise_busy = true

            begin
                na_revise__stop_animation

                unless na_revise__undo_ops(record)
                    UI.beep
                    na_revise__notice("Could not undo the placed #{na_revise__noun} — nothing adjusted")
                    na_revise__forget
                    return false
                end

                na_revise__restore_context(model, record[:user_path])

                reacquired = na_revise__reacquire(record)

                unless reacquired
                    na_revise__redo_ops(record)
                    UI.beep
                    na_revise__notice("Could not find that #{na_revise__noun} again after undoing — put it back with Redo if needed")
                    Na__InsertPrimatives.Na__Debug__Puts "NA REVISE: undid the #{na_revise__noun} and lost its target — Redo attempted"
                    na_revise__forget
                    return false
                end

                if na_revise__rebuild(record, reacquired, value, view)
                    na_revise__animate(@na_revise_record || record, record[:value], value)
                    na_revise__notice(
                        "Adjusted #{na_revise__value_label(record[:value])} → #{na_revise__value_label(value)}" \
                        " — type again to change it, or grab #{na_revise__target_noun} to move on"
                    )
                    return true
                end

                # The new size would not build. Put back the placement that was
                # standing there a moment ago, down the same path that made it.
                reacquired = na_revise__reacquire(record)
                restored   = reacquired ? na_revise__rebuild(record, reacquired, record[:value], view) : false

                UI.beep
                na_revise__notice(
                    restored ? 'That size would not build — left as it was' :
                               'That size would not build, and the original could not be put back — use Redo'
                )
                Na__InsertPrimatives.Na__Debug__Puts "NA REVISE: retype failed, original #{restored ? 'restored' : 'LOST - press Redo'}"
                na_revise__forget unless restored
                false
            ensure
                @na_revise_busy = false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Pop Our Own Undo Step(s)
        # ------------------------------------------------------------
        def na_revise__undo_ops(record)
            count = record[:ops].to_i
            count = 1 if count < 1

            count.times { Sketchup.undo }
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA REVISE: undo raised — #{error.message}"
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put Them Back Again After a Failed Re-Acquire
        # ------------------------------------------------------------
        def na_revise__redo_ops(record)
            count = record[:ops].to_i
            count = 1 if count < 1

            count.times { Sketchup.send_action('editRedo:') }
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put the User Back Where the Undo Found Them
        # A placement made inside a group opened that group and closed it again,
        # and both halves are part of the one undo step. Undoing it can leave
        # the user standing inside a group they never asked to enter, and the
        # rebuild would then run against a context it did not expect.
        # ------------------------------------------------------------
        def na_revise__restore_context(model, wanted)
            return false unless model.respond_to?(:active_path=)

            current = model.active_path
            return false if Na__InsertPrimatives.Na__DeepPick__SameContext?(current, wanted)

            model.active_path = wanted
            true
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA REVISE: could not restore the editing context — #{error.message}"
            begin
                model.active_path = nil
            rescue StandardError
                nil
            end
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | What the Status Bar and Measurements Box Say About It
        # -----------------------------------------------------------------------------

        # FUNCTION | Say Something the Composed Status Line Will Not Wipe
        # onUserText pushes the composed status line the instant it returns, so
        # a message written inline is gone before anyone reads it. Written a
        # beat later instead — the same delay the measurements box is re-armed
        # on. Clearing the cached line lets the ordinary text come back on the
        # next mouse move.
        # ------------------------------------------------------------
        def na_revise__notice(message)
            UI.start_timer(NA_REVISE_NOTICE_DELAY_S, false) do
                begin
                    Sketchup::set_status_text(message, SB_PROMPT)
                    @na_last_status_text = nil
                rescue StandardError
                    nil
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Size as "1200 mm"
        # ------------------------------------------------------------
        def na_revise__value_label(value)
            "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs} mm"
        end
        # ---------------------------------------------------------------

        # FUNCTION | How the Placed Size Reads — Hosts May Add to It
        # ------------------------------------------------------------
        def na_revise__placed_label(record)
            na_revise__value_label(record[:value])
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Retype or Repeat Offer, or an Empty String
        # ------------------------------------------------------------
        def na_revise__status_hint
            if na_revise__available?
                " — placed #{na_revise__placed_label(@na_revise_record)}, type a size to adjust it#{na_revise__sign_hint}"
            elsif na_revise__memory?
                " — dbl-click #{na_revise__target_noun} to repeat #{na_revise__value_label(@na_revise_memory)}"
            else
                ''
            end
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Number to Leave Sitting in the Measurements Box at Idle
        # The placed size while a retype is open — the reminder that it can
        # still be corrected and the value a correction is judged against.
        # Otherwise the remembered size a double-click will repeat.
        # ------------------------------------------------------------
        def na_revise__vcb_value
            return Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_revise_record[:value]).abs.to_s if na_revise__available?
            return Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_revise_memory).abs.to_s        if na_revise__memory?

            ''
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnReviseShared module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN REVISE (SHARED)
# =============================================================================
