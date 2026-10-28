# =============================================================================
# NA INSERT PRIMATIVES - DEEP PROJECT REVISE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnProject__Revise__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnProjectRevise
# AUTHOR     : Noble Architecture
# PURPOSE    : The projection's half of the shared revise contract — retype
#              the offset, repeat the last target, replay the change
# CREATED    : 2026
#
# DESCRIPTION:
# - DrawnReviseShared (06__Tools__DrawnShared) owns what every modifier tool
#   shares: the record, the undo-stack watch, the retype flow, the
#   double-click guard and the animation engine. A projection fits it with
#   one change of meaning: the VALUE is the offset, not a distance — the
#   target already decided the distance.
#     * Type 25 after placing and the projection is made again 25 short of
#       its target; -25 runs it 25 past; 0 puts it back on the target.
#     * Double-click a face and it is carried to the LAST target. Not by the
#       last distance: on a tilted target every corner travels a different
#       one, and the target is what the user meant.
#     * The ghost replays the face sweeping from the old offset to the new.
# - The remembered value the shared code keeps for push and chamfer is a
#   number in the model dictionary. A target is not a number, so the memory
#   half of the contract is answered from Na__Project__Last instead.
#
# THE RECORD CARRIES TOOL STATE, NOT GEOMETRY:
# - As the push tool's does: the faces (found again by an interior point),
#   the target, the locks and the held keys. The rebuild puts those back and
#   runs the one commit path, so a retype cannot drift from a fresh click.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'
require_relative 'Na__InsertPrimatives__DrawnProject__Geometry__'

module Na__InsertPrimatives

    module DrawnProjectRevise

        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Identity and Wording
        # -----------------------------------------------------------------------------

        NA_PJ_MEMORY_KEY = 'Na__DeepProject__LastTarget'.freeze               # <-- Contract only; the target itself lives on the module

        # FUNCTION | Where the Last Value Would Live in the Model Dictionary
        # ------------------------------------------------------------
        def na_revise__memory_key
            NA_PJ_MEMORY_KEY
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Operation Is Called in Messages
        # ------------------------------------------------------------
        def na_revise__noun
            'projection'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Gets Grabbed, in Messages
        # ------------------------------------------------------------
        def na_revise__target_noun
            'a face'
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Leading Sign Means When Retyping
        # ------------------------------------------------------------
        def na_revise__sign_hint
            ' (- runs past the target)'
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Value Reads as the Offset It Is
        # ------------------------------------------------------------
        def na_revise__value_label(value)
            na_pj__offset_words(value)
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Offset as Words: "25 mm short", "25 mm past", "on the target"
        # ------------------------------------------------------------
        def na_pj__offset_words(value)
            millimetres = Na__InsertPrimatives.Na__DrawnFormat__Mm(value).abs
            return 'on the target' if millimetres.zero?

            value.to_f > 0.0 ? "#{millimetres} mm short" : "#{millimetres} mm past"
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Offset as the Measurements Box Shows It
        # ------------------------------------------------------------
        def na_pj__offset_vcb(value)
            Na__InsertPrimatives.Na__DrawnFormat__Mm(value).to_s
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read a Typed Offset — the Sign Is Kept, Zero Is Allowed
        # ------------------------------------------------------------
        # The shared parser, so units and decimals behave as they do everywhere
        # else in the plugin. The sign is read literally rather than as
        # arithmetic against the box: there is no live offset to be relative
        # to, and "-25" is the natural way to say "25 past".
        # ------------------------------------------------------------
        def na_pj__parse_offset(text)
            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'the offset is a single distance' if tokens.length > 1

            token = tokens[0]
            raise ArgumentError, 'no offset entered' if token.nil?

            sign, magnitude = token
            sign == :minus ? -magnitude.to_f.abs : magnitude.to_f.abs
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Retyped Value Is an Offset
        # ------------------------------------------------------------
        def na_revise__parse_retype(text, _record)
            na_pj__parse_offset(text)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Memory Is the Last Target
        # -----------------------------------------------------------------------------

        # FUNCTION | Nothing to Read From the Model — the Target Is Held on the Module
        # ------------------------------------------------------------
        def na_revise__load_memory
            @na_revise_memory = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is There a Target to Repeat?
        # ------------------------------------------------------------
        def na_revise__memory?
            !Na__InsertPrimatives.Na__Project__Last.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Carry the Grabbed Face to the Last Target, or Say Why Not
        # ------------------------------------------------------------
        def na_revise__repeat_or_refuse(view)
            last = Na__InsertPrimatives.Na__Project__Last

            unless last
                UI.beep
                Sketchup::set_status_text('Nothing to repeat yet — carry a face to a target first', SB_PROMPT)
                return false
            end

            return false unless na_revise__repeat_allowed?

            na_revise__apply_repeat(last, view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Place the Grabbed Face on the Remembered Target
        # ------------------------------------------------------------
        # An object remembered as the target may hold the face just taken, and
        # a face cannot be carried into its own solid; the live direction keys
        # and the live offset apply, as they do to a fresh click.
        # ------------------------------------------------------------
        def na_revise__apply_repeat(last, view)
            if last[:kind] == :object && na_pj__holds_source?(last[:instance])
                UI.beep
                na_revise__notice("Not repeated — #{last[:name]} holds that face")
                return false
            end

            @na_pj_target = last
            na_pj__resolve
            na_pj__place(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Retype or Repeat Offer, or an Empty String
        # ------------------------------------------------------------
        def na_revise__status_hint
            if na_revise__available?
                " — placed #{na_pj__offset_words(@na_revise_record[:value])}; type an offset to re-make it#{na_revise__sign_hint}"
            elsif na_revise__memory?
                " — dbl-click a face to carry it to #{Na__InsertPrimatives.Na__Project__Last[:name]}"
            else
                ''
            end
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Offset Left Sitting in the Measurements Box at Idle
        # ------------------------------------------------------------
        def na_revise__vcb_value
            return na_pj__offset_vcb(@na_revise_record[:value]) if na_revise__available?

            na_pj__offset_vcb(@na_pj_offset)
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Capture
        # -----------------------------------------------------------------------------

        # FUNCTION | Arm the Retype With Everything the Commit Path Reads
        # ------------------------------------------------------------
        # Counted off the collections the faces are in NOW, after the
        # placement: that is what the sanity check compares against later.
        # ------------------------------------------------------------
        def na_pj__capture(sources, snaps, target, settings, ghost, model)
            return na_revise__forget if snaps.empty? || snaps.any?(&:nil?)

            members = sources.each_with_index.map do |source, index|
                { :target => source[:target], :snapshot => snaps[index] }
            end

            collections = members.map { |member| na_pj__live_entities(member) }.compact.uniq
            return na_revise__forget if collections.empty?

            na_revise__arm({
                :kind        => :projection,
                :members     => members,
                :target      => target,
                :value       => settings[:offset].to_f,
                :sense       => @na_pj_sense,
                :edge_lock   => @na_pj_edge_lock,
                :axis_lock   => @na_axis_lock,
                :shift       => @na_shift_held ? true : false,
                :alt         => @na_alt_held ? true : false,
                :quads       => settings[:quads] ? true : false,
                :preselected => @na_pj_preselected ? true : false,
                :anchor      => @na_point_a,
                :user_path   => snaps.first[:user_path],
                :counts      => collections.map { |entities| [entities, na_revise__entity_count(entities)] },
                :ops         => 1,
                :ghost       => ghost
            })
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA PROJECT: retype not armed — #{error.message}"
            na_revise__forget
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Live Collection a Member's Face Lives In
        # ------------------------------------------------------------
        def na_pj__live_entities(member)
            face = member[:target][:face]

            if face && face.valid?
                parent = face.parent
                return parent.entities if parent.respond_to?(:entities)
            end

            fallback = member[:snapshot][:entities]
            na_revise__entity_count(fallback).nil? ? nil : fallback
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Everything the Ghost Needs, Copied Out at Their Starting Positions
        # ------------------------------------------------------------
        # The solved sources carry world loops, triangles and motions and no
        # live entity at all, so the ghost can be re-solved at any offset on
        # any frame without touching the model.
        # ------------------------------------------------------------
        def na_pj__build_ghost(sources, target, settings)
            {
                :sources => sources.map { |source| source.reject { |key, _value| key == :target } },
                :target  => target,
                :sense   => settings[:sense],
                :quads   => settings[:quads] ? true : false
            }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Re-Acquire and Rebuild
        # -----------------------------------------------------------------------------

        # FUNCTION | Find Every Face Again Where the Undo Put It Back
        # Returns the recorded targets wearing the re-found faces, or nil.
        # ------------------------------------------------------------
        def na_revise__reacquire(record)
            record[:members].map do |member|
                entities = na_pj__live_entities(member)
                return nil unless entities

                face = na_pj__face_at(entities, member)
                return nil unless face

                member[:target].merge(:face => face)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is There a Face at the Recorded Interior Point?
        # The recorded face object first, because it is one test and very
        # often the answer; then the collection, as the push tool does it.
        # ------------------------------------------------------------
        def na_pj__face_at(entities, member)
            snapshot = member[:snapshot]
            wanted   = snapshot[:interior]
            face     = member[:target][:face]
            return nil unless wanted

            if face && face.valid? && face.classify_point(wanted) == Sketchup::Face::PointInside
                return face
            end

            entities.grep(Sketchup::Face).each do |candidate|
                next unless candidate.valid?
                next unless candidate.normal.samedirection?(snapshot[:normal])
                return candidate if candidate.classify_point(wanted) == Sketchup::Face::PointInside
            end

            nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Commit Path Again at a New Offset
        # ------------------------------------------------------------
        def na_revise__rebuild(record, targets, value, view)
            placed = false

            na_pj__wearing(record, targets, value) do
                placed = na_pj__commit(view)
            end

            placed ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Wear the Tool State the Recorded Projection Was Made In
        # ------------------------------------------------------------
        # The held keys and the locks are live user state and are put back
        # exactly as they were found. The offset is not: the one just typed
        # becomes the offset in force, as typing it before a click would have.
        # ------------------------------------------------------------
        def na_pj__wearing(record, targets, value)
            held = [@na_shift_held, @na_alt_held, @na_axis_lock, @na_pj_edge_lock, @na_pj_sense]

            @na_revise_replaying = record
            @na_shift_held       = record[:shift]
            @na_alt_held         = record[:alt]
            @na_axis_lock        = record[:axis_lock]
            @na_pj_edge_lock     = record[:edge_lock]
            @na_pj_sense         = record[:sense]
            @na_pj_offset        = value.to_f
            @na_pj_sources       = targets.map { |target| na_pj__build_source(target) }.compact
            @na_pj_preselected   = record[:preselected]
            @na_pj_target        = record[:target]
            @na_point_a          = record[:anchor]
            @na_state            = :picking_target
            na_pj__resolve

            yield
        ensure
            @na_shift_held, @na_alt_held, @na_axis_lock, @na_pj_edge_lock, @na_pj_sense = held
            @na_revise_replaying = nil
            na_drawn__reset_pick_state unless @na_state == :idle             # <-- A rebuild that would not build leaves nothing half-taken
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract — The Ghost
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw Every Face Carried to an Interpolated Offset
        # ------------------------------------------------------------
        def na_revise__draw_ghost(view, ghost, value, from_value, to_value)
            anchor = nil

            ghost[:sources].each do |source|
                solution = Na__InsertPrimatives.Na__Project__Solve(
                    source, ghost[:target], { :offset => value, :sense => ghost[:sense] }
                )
                next unless solution[:ok]

                na_pj__draw_solution(view, source, solution, ghost[:quads], false)
                anchor ||= solution[:loops][0][0]
            end
            return false unless anchor

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, anchor,
                ["Offset #{na_pj__offset_words(from_value)} → #{na_pj__offset_words(to_value)}"],
                14, -26, NA_DRAWN_TEXT_ACCENT_COLOR
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Ghost Occupies at an Offset, for the Extents
        # ------------------------------------------------------------
        def na_revise__ghost_points(ghost, value)
            ghost[:sources].flat_map do |source|
                solution = Na__InsertPrimatives.Na__Project__Solve(
                    source, ghost[:target], { :offset => value, :sense => ghost[:sense] }
                )
                points = source[:loops].flatten

                solution[:ok] ? points + solution[:loops].flatten : points
            end
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnProjectRevise module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PROJECT REVISE
# =============================================================================
