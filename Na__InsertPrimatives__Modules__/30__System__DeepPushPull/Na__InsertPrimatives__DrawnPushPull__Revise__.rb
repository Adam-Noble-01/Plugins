# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL REVISE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__Revise__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnPushPullRevise
# AUTHOR     : Noble Architecture
# PURPOSE    : Retype the distance of a push AFTER it has already been placed
# CREATED    : 2026
#
# DESCRIPTION:
# - Native Push/Pull leaves the measurements box live after the click that
#   places the extrusion: type 1200, Enter, and the push you just made becomes
#   1200 — again and again until you start something else. Fredo's Joint
#   Push/Pull does the same. This tool did not, and it was the one step in the
#   whole plugin that stopped feeling like SketchUp.
# - This module is that step. It records everything a completed push was made
#   from, and a typed distance while idle rebuilds it at the new size.
#
# WHY REBUILD RATHER THAN TOP UP:
# - The obvious cheap version is to push the ALREADY MOVED face by the
#   difference. It falls apart immediately: the quad ring would be stitched a
#   second time, a slope shear would compound on top of itself, a loop cut has
#   no face that moved at all, and a sign flip would have to drag the face back
#   through its own start plane and hope the walls it made get reabsorbed.
# - So the push is taken off the undo stack instead and RE-RUN from the state
#   it was made in. The result of typing 1200 is byte-for-byte the result of
#   having dragged 1200 in the first place, in every mode, because it is
#   literally the same commit path running again. Repeat entries cost one undo
#   step in total rather than one each, which is what native does too.
#
# THE SIGN IS A DIRECTION HERE, NOT ARITHMETIC:
# - Everywhere else in this plugin a leading + or - is relative arithmetic
#   against the live drag: "-25" means 25 less than what the mouse is showing.
#   There is no drag to be relative to once the push is placed, and what a
#   SketchUp user reaches for at that moment is the other thing entirely —
#   type a minus and the extrusion turns round.
# - So in this one state the sign names the direction: 1200 is 1200 the way you
#   dragged, -1200 is 1200 the other way, and the anchor stays the ORIGINAL
#   drag direction so typing -1200 then 1200 lands you back where you were
#   rather than walking off in one direction.
#
# WHY IT REFUSES RATHER THAN GUESSES:
# - Sketchup.undo pops whatever is on top of the stack, and if that is not our
#   push then calling it destroys somebody else's work. So before any undo is
#   attempted the model is asked whether the push is still the thing standing
#   there: the entity count of the definition it was made in, and a face where
#   the push left one. Either answer wrong and the record is dropped with a
#   line saying so, and nothing is undone.
#
# NOT ARMED AFTER A LOOP CUT:
# - The inward-with-quads gesture moves no face, so there is no "where the push
#   left it" to test the undo stack against, and an unverifiable undo is not
#   worth the convenience. A loop cut ends the chance to retype, and says so.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'

module Na__InsertPrimatives

    module DrawnPushPullRevise

        # -----------------------------------------------------------------------------
        # REGION | Record Lifetime
        # -----------------------------------------------------------------------------

        # FUNCTION | Blank Slate — Constructor Only
        # ------------------------------------------------------------
        def na_drawn__init_replay_state
            @na_pp_replay    = nil
            @na_pp_replaying = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drop the Chance to Retype the Last Push
        # @na_pp_replaying is deliberately left alone: it says a rebuild is
        # RUNNING, it is owned by na_drawn__with_replay_state, and a commit
        # that fails part way through one must not clear it out from under it.
        # ------------------------------------------------------------
        def na_drawn__forget_replay
            @na_pp_replay = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say Something the Composed Status Line Will Not Wipe
        # ------------------------------------------------------------
        # onUserText pushes the composed status line the instant it returns, so
        # a refusal written inline is gone before anyone reads it. Written a
        # beat later instead — the same trick, and the same delay, the
        # measurements box is re-armed on. Clearing the cached line is what
        # lets the ordinary status text come back on the next mouse move.
        # ------------------------------------------------------------
        def na_drawn__replay_notice(message)
            UI.start_timer(0.1, false) do
                begin
                    Sketchup::set_status_text(message, SB_PROMPT)
                    @na_last_status_text = nil
                rescue StandardError
                    nil
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is There a Placed Push Still Waiting to Be Retyped?
        # ------------------------------------------------------------
        # Deliberately cheap: this is asked by the status line and the
        # measurements box on every mouse move. The expensive question — is the
        # push still the top of the undo stack — is asked once, at the moment a
        # distance is actually typed.
        # ------------------------------------------------------------
        def na_drawn__replay_available?
            return false unless @na_state == :idle
            return false unless @na_pp_replay

            na_drawn__replay_entities_live?(@na_pp_replay[:entities])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Entities Collection Still Alive?
        # ------------------------------------------------------------
        # Sketchup::Entities is a COLLECTION, not an Entity, so it has no
        # valid? to ask — calling one would raise NoMethodError, and a rescue
        # around it would quietly answer "no" forever and take the whole
        # feature with it. Touching a collection whose definition has been
        # purged raises instead, so it is asked its length and the raise is
        # the answer.
        # ------------------------------------------------------------
        def na_drawn__replay_entities_live?(entities)
            return false unless entities

            entities.length
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Anything That Disarms Revise Also Drops the Record
        # The mixin disarms on activate, which is exactly when a record from a
        # previous session of the tool must not survive.
        # ------------------------------------------------------------
        def na_drawn__disarm_revise
            super
            na_drawn__forget_replay
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Capture
        # -----------------------------------------------------------------------------

        # FUNCTION | Read the Face's Own Space BEFORE Anything Moves It
        # ------------------------------------------------------------
        # Two things, and both only exist while the face is still untouched: a
        # point strictly inside it, and the collection it lives in. The interior
        # point is the whole identification scheme — carried along the push it
        # says where the face ended up, and left where it is it says where the
        # face goes back to.
        # ------------------------------------------------------------
        def na_drawn__replay_snapshot(target, model)
            face = target && target[:face]
            return nil unless face && face.valid?

            parent   = face.parent
            entities = parent.respond_to?(:entities) ? parent.entities : model.active_entities
            interior = Na__InsertPrimatives.Na__SlopePush__InteriorPoint(face)
            return nil unless entities && interior

            {
                :entities  => entities,
                :interior  => interior,
                :normal    => face.normal,
                :user_path => (model.respond_to?(:active_path) ? model.active_path : nil)
            }
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arm the Retype With Everything the Commit Path Reads
        # ------------------------------------------------------------
        # The record carries tool state, not geometry: restore these few
        # instance variables and na_drawn__commit_push recomputes the offset,
        # the slope split and the quad decision exactly as it did the first
        # time. That is why a replay cannot drift from a fresh drag — there is
        # only one implementation of what a push is.
        # ------------------------------------------------------------
        def na_drawn__record_replay(target, snapshot, local_offset, sloped, cutting)
            return na_drawn__forget_replay unless snapshot && local_offset
            return na_drawn__forget_replay if cutting                         # <-- See the header: a cut leaves nothing to verify against

            # Counted off the collection the face is in NOW, not the one it was
            # in before the push: a group whose definition the edit made unique
            # has moved, and a count taken from the collection it left would
            # never match again.
            entities = na_drawn__replay_live_entities(target[:face], snapshot[:entities])
            return na_drawn__forget_replay unless entities

            # The anchor is the direction the MOUSE chose, and it is carried
            # through every retype so a typed minus always means "the other way
            # from how I dragged" rather than "the other way from last time".
            anchor = @na_pp_replaying ? @na_pp_replaying[:anchor_sign].to_f : @na_sign_d.to_f

            @na_pp_replay = {
                :target      => target,
                :entities    => entities,
                :interior    => snapshot[:interior],
                :normal      => snapshot[:normal],
                :user_path   => snapshot[:user_path],
                :count       => na_drawn__replay_entity_count(entities),
                :offset      => local_offset,
                :size        => @na_size_d.to_f.abs,
                :sign        => @na_sign_d.to_f,
                :anchor_sign => anchor,
                :axis_lock   => @na_axis_lock,
                :slope       => @na_pp_slope,
                :slope_mode  => sloped ? true : false,
                :quad        => na_drawn__quad_mode?
            }
        rescue StandardError => error
            na_drawn__trace("replay not armed — #{error.message}")
            na_drawn__forget_replay
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Many Entities the Definition Holds Right Now
        # ------------------------------------------------------------
        def na_drawn__replay_entity_count(entities)
            return nil unless entities

            entities.length.to_i
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Is the Recorded Push Still the Thing on Top of the Stack?
        # -----------------------------------------------------------------------------

        # FUNCTION | The Live Collection a Face Lives In
        # A group whose definition was made unique by the edit hands back a new
        # collection, so the face is asked first and the recorded one is only
        # the fallback for a face that did not survive.
        # ------------------------------------------------------------
        def na_drawn__replay_live_entities(face, fallback)
            if face && face.valid?
                parent = face.parent
                return parent.entities if parent.respond_to?(:entities)
            end

            na_drawn__replay_entities_live?(fallback) ? fallback : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | That Same Question, Asked of a Record
        # ------------------------------------------------------------
        def na_drawn__replay_entities(record)
            face = record[:target] && record[:target][:face]

            na_drawn__replay_live_entities(face, record[:entities])
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is There a Face Sitting at the Recorded Point?
        # ------------------------------------------------------------
        # The same identification Na__SlopePush__MovedFace does, written out
        # rather than called, because this one also has to ask about a travel of
        # NOTHING — where the face started — and Point3d#offset will not take a
        # zero vector. The recorded face object is tried first because it is one
        # test and very often the answer; only then is the definition swept.
        # ------------------------------------------------------------
        def na_drawn__replay_face_at(entities, record, travel, normal = nil)
            wanted = record[:interior]
            return nil unless entities && wanted

            wanted = wanted.offset(travel) if travel && travel.length > 0
            face   = record[:target][:face]

            if face && face.valid? &&
               face.classify_point(wanted) == Sketchup::Face::PointInside
                return face
            end

            entities.grep(Sketchup::Face).each do |candidate|
                next unless candidate.valid?
                next unless normal.nil? || candidate.normal.samedirection?(normal)
                return candidate if candidate.classify_point(wanted) == Sketchup::Face::PointInside
            end

            nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Refuse to Undo Anything That Is Not Our Own Push
        # ------------------------------------------------------------
        # Two tests, and they cover each other's blind spots:
        #
        # - THE COUNT. A push adds walls, so the definition holds more entities
        #   after it than before. A user who has already pressed Ctrl+Z has put
        #   that count back. Blind to a slope STRETCH, which creates nothing.
        # - THE PLACE. Either a face where the push left one, or — for a push
        #   that went clean through and consumed its own face — nothing at all
        #   where it started. An undo puts that face back, so finding one at the
        #   start point is proof the push is no longer standing. Blind to a
        #   push that happens not to change what is at either point, which is
        #   what the count is there for.
        #
        # Failing either means the top of the undo stack is not ours, and the
        # only safe move is to drop the record without touching it.
        # ------------------------------------------------------------
        def na_drawn__replay_still_current?(record)
            entities = na_drawn__replay_entities(record)
            return false unless entities

            counted = na_drawn__replay_entity_count(entities)
            return false unless counted && record[:count] && counted == record[:count]

            return true if na_drawn__replay_face_at(entities, record, record[:offset])

            na_drawn__replay_face_at(entities, record, nil).nil?
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find the Face Again Where the Undo Put It Back
        # ------------------------------------------------------------
        def na_drawn__replay_reacquire(record)
            entities = na_drawn__replay_entities(record)
            return nil unless entities

            na_drawn__replay_face_at(entities, record, nil, record[:normal])
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Retype Itself
        # -----------------------------------------------------------------------------

        # FUNCTION | Read a Typed Distance as a Signed Push and Rebuild
        # ------------------------------------------------------------
        # The parser is the shared one, so units and decimals behave exactly as
        # they do mid-drag. Only the SIGN is read differently — see the header.
        # ------------------------------------------------------------
        def na_drawn__revise_from_vcb(text, view)
            record = @na_pp_replay

            unless record
                UI.beep
                Sketchup::set_status_text('Nothing placed to adjust — grab a face first', SB_PROMPT)
                return false
            end

            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'push takes a single distance' if tokens.length > 1

            token = tokens[0]
            raise ArgumentError, 'no distance entered' if token.nil?

            sign, magnitude = token

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(magnitude)
                raise ArgumentError,
                      "distance would be #{Na__InsertPrimatives.Na__DrawnFormat__Mm(magnitude)}mm — must be positive"
            end

            # The anchor, never the last value entered: -1200 then 1200 has to
            # land back where the first push was rather than walking on.
            direction = (sign == :minus ? -1.0 : 1.0) * record[:anchor_sign].to_f

            na_drawn__revise_push(view, magnitude.to_f.abs, direction)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take the Push Back Off the Stack and Make It Again
        # ------------------------------------------------------------
        # The record is left exactly as it was until a rebuild has actually
        # landed, because it is also the recipe for putting the user's own push
        # back if the new distance turns out to be one the geometry will not
        # take. An undo with nothing rebuilt after it is the one outcome this
        # must never leave behind.
        # ------------------------------------------------------------
        def na_drawn__revise_push(view, size, sign)
            record = @na_pp_replay
            model  = Sketchup.active_model
            return false unless record && model

            unless na_drawn__replay_still_current?(record)
                UI.beep
                na_drawn__replay_notice('That push is no longer the last thing done — nothing adjusted')
                Na__InsertPrimatives.Na__Debug__Puts 'NA PUSH/PULL: retype refused — the recorded push is not on top of the undo stack'
                na_drawn__forget_replay
                return false
            end

            Sketchup.undo
            na_drawn__replay_restore_context(model, record)

            face = na_drawn__replay_reacquire(record)

            unless face
                UI.beep
                na_drawn__replay_notice('Could not find that face again after undoing — use Redo')
                Na__InsertPrimatives.Na__Debug__Puts 'NA PUSH/PULL: retype undid the push and lost the face — attempting Redo'
                begin
                    Sketchup.send_action('editRedo:')
                rescue StandardError
                    nil
                end
                na_drawn__forget_replay
                return false
            end

            target = record[:target].merge(:face => face)
            return true if na_drawn__replay_rebuild(record, target, view, size, sign)

            # The new distance would not build. Put back the push that was
            # standing there a moment ago, down the same path that made it.
            restored = na_drawn__replay_rebuild(record, target, view, record[:size], record[:sign])

            said =
                if restored then 'That distance would not build — the push was left as it was'
                else             'That distance would not build, and the original could not be put back — use Redo'
                end

            UI.beep
            na_drawn__replay_notice(said)
            Na__InsertPrimatives.Na__Debug__Puts "NA PUSH/PULL: retype failed, original #{restored ? 'restored' : 'LOST - press Redo'}"
            na_drawn__forget_replay unless restored
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Commit Path Again at a Given Signed Distance
        # ------------------------------------------------------------
        def na_drawn__replay_rebuild(record, target, view, size, sign)
            placed = false

            na_drawn__with_replay_state(record, target, size, sign) do
                placed = na_drawn__commit_push(view)
            end

            placed ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Wear the Tool State the Recorded Push Was Made In
        # ------------------------------------------------------------
        # SHIFT and the axis lock are live user state and are put back exactly
        # as they were found — the user is still holding, or not holding, what
        # they were holding a moment ago. @na_pp_replaying is what tells the
        # rest of the tool a replay is running: the quad mode override and the
        # console headline both read it, and record_replay reads it to carry the
        # original drag direction forward into the new record.
        # ------------------------------------------------------------
        def na_drawn__with_replay_state(record, target, size, sign)
            held_shift = @na_shift_held
            held_axis  = @na_axis_lock

            @na_pp_replaying = record
            @na_pp_target    = target
            @na_pp_slope     = record[:slope]
            @na_shift_held   = record[:slope_mode] ? true : false
            @na_axis_lock    = record[:axis_lock]
            @na_size_d       = size.to_f.abs
            @na_sign_d       = sign.to_f

            yield
        ensure
            @na_shift_held   = held_shift
            @na_axis_lock    = held_axis
            @na_pp_replaying = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put the User Back Where the Undo Found Them
        # ------------------------------------------------------------
        # A push made inside a group opened that group and closed it again, and
        # both halves are part of the one undo step. Undoing it can therefore
        # leave the user standing inside the group they never asked to enter,
        # and the replay would then run against a context it did not expect.
        # ------------------------------------------------------------
        def na_drawn__replay_restore_context(model, record)
            return false unless model.respond_to?(:active_path=)

            wanted  = record[:user_path]
            current = model.active_path
            return false if na_drawn__same_context?(current, wanted)

            model.active_path = wanted
            na_drawn__trace('replay restored the editing context after the undo')
            true
        rescue StandardError => error
            na_drawn__trace("replay could not restore the editing context — #{error.message}")
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

        # FUNCTION | The Placed Distance, in Millimetres, Unsigned
        # ------------------------------------------------------------
        def na_drawn__replay_distance_mm
            return '0' unless @na_pp_replay

            Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_pp_replay[:size]).abs.to_s
        rescue StandardError
            '0'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Placed Push Currently Running Against the Drag?
        # ------------------------------------------------------------
        def na_drawn__replay_reversed?
            return false unless @na_pp_replay

            @na_pp_replay[:sign].to_f * @na_pp_replay[:anchor_sign].to_f < 0.0
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Retype Offer, or an Empty String
        # ------------------------------------------------------------
        def na_drawn__replay_hint
            return '' unless na_drawn__replay_available?

            reversed = na_drawn__replay_reversed? ? ' REVERSED' : ''
            " — placed #{na_drawn__replay_distance_mm} mm#{reversed}, type a distance to adjust it (- reverses)"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullRevise module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL REVISE MODULE
# =============================================================================
