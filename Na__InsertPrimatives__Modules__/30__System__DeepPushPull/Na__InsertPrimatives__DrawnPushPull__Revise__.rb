# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL REVISE
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__Revise__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnPushPullRevise
# AUTHOR     : Noble Architecture
# PURPOSE    : The push/pull half of the shared revise contract — capture,
#              re-acquire, rebuild, repeat and the ghost
# CREATED    : 2026
#
# DESCRIPTION:
# - DrawnReviseShared (06__Tools__DrawnShared) owns the mechanics every
#   modifier tool has in common: the record, the undo-stack watch, the retype
#   flow, the double-click guard, the remembered value and the animation
#   engine. This module supplies what only a push knows:
#     * what to remember about a placed push so it can be run again
#     * how to find the face again once the push has been undone
#     * how to run the commit path wearing the state the push was made in
#     * what a leading sign means when a distance is retyped
#     * what the sweeping ghost looks like
#
# THE SIGN IS A DIRECTION HERE, NOT ARITHMETIC:
# - Everywhere else in this plugin a leading + or - is relative arithmetic
#   against the live drag: "-25" means 25 less than what the mouse is showing.
#   There is no drag to be relative to once the push is placed, and what a
#   SketchUp user reaches for at that moment is the other thing entirely —
#   type a minus and the extrusion turns round.
# - So in this one state the sign names the direction: 1200 is 1200 the way
#   you dragged, -1200 is 1200 the other way, and the anchor stays the
#   ORIGINAL drag direction so typing -1200 then 1200 lands you back where you
#   were rather than walking off in one direction.
#
# THE RECORD CARRIES TOOL STATE, NOT GEOMETRY:
# - Restore the handful of instance variables the commit path reads — target,
#   axis lock, slope candidate, whether SHIFT was down, whether QUADS were
#   armed — and na_drawn__commit_push recomputes the offset, the slope split
#   and the quad decision itself. There is still only one implementation of
#   what a push is, which is why a retype cannot drift from a fresh drag.
# - Quad mode is read from the record and not from the live setting: pressing
#   TAB between placing and retyping must not quietly add or drop a quad line.
#
# LOOP CUTS ARE ARMED TOO:
# - 5.1.0 refused to arm after an inward quad drag because it had no face
#   movement to verify the undo stack against. The watch has made that
#   verification unnecessary, so a loop cut retypes like anything else: the
#   inset moves to the new distance and the ghost shows the ring travelling.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnRevise__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'
require_relative '../03__AppUtils/Na__InsertPrimatives__DrawnVcbArithmetic__'

module Na__InsertPrimatives

    module DrawnPushPullRevise

        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Identity and Wording
        # -----------------------------------------------------------------------------

        # FUNCTION | Where the Last Distance Lives in the Model Dictionary
        # Shared by the 3D and 2D variants on purpose: to the user they are one
        # tool, and a distance pulled in elevation is a distance to repeat in
        # perspective.
        # ------------------------------------------------------------
        def na_revise__memory_key
            NA_TOOL_MEMORY_PUSH_PULL_KEY
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Operation Is Called in Messages
        # ------------------------------------------------------------
        def na_revise__noun
            'push'
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
            ' (- reverses)'
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Placed Distance, Flagged When It Runs Against the Drag
        # ------------------------------------------------------------
        def na_revise__placed_label(record)
            reversed = record[:sign].to_f * record[:anchor_sign].to_f < 0.0
            "#{na_revise__value_label(record[:value])}#{reversed ? ' REVERSED' : ''}"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Capture
        # -----------------------------------------------------------------------------

        # FUNCTION | Read the Face's Own Space BEFORE Anything Moves It
        # Two things, and both only exist while the face is still untouched: a
        # point strictly inside it, and the collection it lives in. The interior
        # point is the whole identification scheme — carried along the push it
        # says where the face ended up, and left where it is it says where the
        # face goes back to.
        # ------------------------------------------------------------
        def na_revise__snapshot(target, model)
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
        # Called after a successful push, while every number it was made from
        # is still in scope. During a rebuild the anchor direction and the
        # ghost are carried forward from the record being rebuilt, so a typed
        # minus always means "the other way from how I dragged" and the ghost
        # keeps sweeping from the face's ORIGINAL position.
        # ------------------------------------------------------------
        def na_revise__capture(target, snapshot, local_offset, sloped, cutting)
            return na_revise__forget unless snapshot && local_offset

            # Counted off the collection the face is in NOW, not the one it was
            # in before the push: a group whose definition the edit made unique
            # has moved, and a count taken from the collection it left would
            # never match again.
            entities = na_revise__live_entities(target[:face], snapshot[:entities])
            return na_revise__forget unless entities

            replaying = @na_revise_replaying
            anchor    = replaying ? replaying[:anchor_sign].to_f : @na_sign_d.to_f
            ghost     = replaying ? replaying[:ghost] : na_revise__build_ghost(target)

            na_revise__arm({
                :target      => target,
                :entities    => entities,
                :interior    => snapshot[:interior],
                :normal      => snapshot[:normal],
                :user_path   => snapshot[:user_path],
                :counts      => [[entities, na_revise__entity_count(entities)]],
                :ops         => 1,
                :offset      => local_offset,
                :size        => @na_size_d.to_f.abs,
                :sign        => @na_sign_d.to_f,
                :value       => @na_size_d.to_f.abs * @na_sign_d.to_f,
                :anchor_sign => anchor,
                :axis_lock   => @na_axis_lock,
                :slope       => @na_pp_slope,
                :slope_mode  => sloped ? true : false,
                :quad        => na_drawn__quad_mode?,
                :cut         => cutting ? true : false,
                :ghost       => ghost
            })
        rescue StandardError => error
            na_drawn__trace("retype not armed — #{error.message}")
            na_revise__forget
        end
        # ---------------------------------------------------------------

        # FUNCTION | Everything the Ghost Needs, Copied Out While the Face Is Cached
        # The cached loop and triangles are the face at its ORIGINAL position
        # — exactly where every rebuild starts from — so the same ghost serves
        # every later retype. Cloned, because the caches are rebuilt on hover.
        # ------------------------------------------------------------
        def na_revise__build_ghost(target)
            direction = na_drawn__travel_direction || target[:world_normal]
            edge      = @na_pp2d_edge_world                                   # <-- Only the 2D variant ever sets this

            {
                :loop        => (@na_pp_loop || []).map { |point| point.clone },
                :triangles   => (@na_pp_triangles || []).map { |points| points.map { |point| point.clone } },
                :direction   => direction ? direction.clone : nil,
                :axis_factor => na_drawn__axis_travel_factor,
                :quad        => na_drawn__quad_mode?,
                :edge_world  => (edge && edge.length == 2) ? edge.map { |point| point.clone } : nil
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Live Collection a Face Lives In
        # A group whose definition was made unique by the edit hands back a new
        # collection, so the face is asked first and the recorded one is only
        # the fallback for a face that did not survive the push.
        # ------------------------------------------------------------
        def na_revise__live_entities(face, fallback)
            if face && face.valid?
                parent = face.parent
                return parent.entities if parent.respond_to?(:entities)
            end

            na_revise__entity_count(fallback).nil? ? nil : fallback
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Re-Acquire After the Undo
        # -----------------------------------------------------------------------------

        # FUNCTION | Is There a Face Sitting at the Recorded Point?
        # The same identification Na__SlopePush__MovedFace does, written out
        # rather than called, because this one also has to ask about a travel
        # of NOTHING — where the face started — and Point3d#offset will not
        # take a zero vector. The recorded face object is tried first because
        # it is one test and very often the answer; only then is the
        # definition swept.
        # ------------------------------------------------------------
        def na_revise__face_at(entities, record, travel, normal = nil)
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

        # FUNCTION | Find the Face Again Where the Undo Put It Back
        # Returns the recorded target wearing the re-found face, or nil.
        # ------------------------------------------------------------
        def na_revise__reacquire(record)
            entities = na_revise__live_entities(record[:target][:face], record[:entities])
            return nil unless entities

            face = na_revise__face_at(entities, record, nil, record[:normal])
            return nil unless face

            record[:target].merge(:face => face)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract — Rebuild and Repeat
        # -----------------------------------------------------------------------------

        # FUNCTION | Run the Commit Path Again at a Signed Distance
        # ------------------------------------------------------------
        def na_revise__rebuild(record, target, value, view)
            placed = false

            na_revise__wearing(record, target, value) do
                placed = na_drawn__commit_push(view)
            end

            placed ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Wear the Tool State the Recorded Push Was Made In
        # SHIFT and the axis lock are live user state and are put back exactly
        # as they were found — the user is still holding, or not holding, what
        # they were holding a moment ago. @na_revise_replaying is what tells
        # the rest of the tool a rebuild is running: the quad mode override
        # and the console headline read it, and capture reads it to carry the
        # original drag direction and the ghost into the new record.
        # ------------------------------------------------------------
        def na_revise__wearing(record, target, value)
            held_shift = @na_shift_held
            held_axis  = @na_axis_lock

            @na_revise_replaying = record
            @na_pp_target        = target
            @na_pp_slope         = record[:slope]
            @na_shift_held       = record[:slope_mode] ? true : false
            @na_axis_lock        = record[:axis_lock]
            @na_size_d           = value.to_f.abs
            @na_sign_d           = value.to_f < 0.0 ? -1.0 : 1.0

            yield
        ensure
            @na_shift_held       = held_shift
            @na_axis_lock        = held_axis
            @na_revise_replaying = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read a Typed Distance as a Signed Push
        # The parser is the shared one, so units and decimals behave exactly as
        # they do mid-drag. Only the SIGN is read differently — see the header.
        # ------------------------------------------------------------
        def na_revise__parse_retype(text, record)
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
            magnitude.to_f.abs * direction
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push the Grabbed Face by the Remembered Signed Distance
        # The sign is relative to the direction the drag measures along — the
        # face normal, or the slope under SHIFT — so "300 out" repeats as 300
        # out of whatever face was double-clicked, and an inward loop cut
        # repeats as an inward loop cut.
        # ------------------------------------------------------------
        def na_revise__apply_repeat(value, view)
            @na_size_d = value.to_f.abs
            @na_sign_d = value.to_f < 0.0 ? -1.0 : 1.0
            na_drawn__lock_slot(:d)
            na_drawn__trace("double-click repeats #{Na__InsertPrimatives.Na__DrawnFormat__Mm(value)}mm")
            na_drawn__commit_push(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Host Contract — The Ghost
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Face Swept to an Interpolated Distance
        # The same picture the live drag paints — start loop, moved face, the
        # rungs between, the travel arrow — at whatever distance the sweep has
        # reached, with the old and new numbers written on it. An inward quad
        # value draws as the loop cut it is, because that is what the model
        # holds at that value.
        # ------------------------------------------------------------
        def na_revise__draw_ghost(view, ghost, value, from_value, to_value)
            loop_points = ghost[:loop]
            direction   = ghost[:direction]
            return false if loop_points.nil? || loop_points.empty? || direction.nil?

            factor  = ghost[:axis_factor].to_f
            factor  = 1.0 if factor.abs < 0.0001
            world   = value.to_f / factor                                     # <-- An axis lock measures along the axis; the face travels along its normal
            quads   = ghost[:quad] ? true : false
            cutting = quads && world < 0.0
            colours = self.class

            moved_loop = loop_points.map do |point|
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, direction, world)
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(
                view, loop_points,
                quads ? colours::NA_PP_QUAD_BORDER : colours::NA_PP_HOVER_BORDER, 1
            )

            if cutting
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, ghost[:triangles], colours::NA_PP_HOVER_FILL)
                na_revise__draw_ghost_rungs(view, loop_points, moved_loop, colours::NA_PP_QUAD_BORDER)
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, moved_loop, colours::NA_PP_QUAD_BORDER, 3)
            else
                moved_triangles = (ghost[:triangles] || []).map do |points|
                    points.map { |point| Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, direction, world) }
                end

                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, moved_triangles, colours::NA_PP_RESULT_FILL)
                na_revise__draw_ghost_rungs(view, loop_points, moved_loop, colours::NA_PP_RESULT_BORDER)
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, moved_loop, colours::NA_PP_RESULT_BORDER, 2)
            end

            na_revise__draw_ghost_sweep(view, ghost, direction, world, cutting)

            if world.abs > 0.0
                Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(
                    view, loop_points.first, world < 0.0 ? direction.reverse : direction
                )
            end

            from_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(from_value).abs
            to_mm   = Na__InsertPrimatives.Na__DrawnFormat__Mm(to_value).abs
            verb    = cutting ? 'Loop cut' : na_revise__noun.capitalize

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, moved_loop.first,
                ["#{verb} #{from_mm} → #{to_mm} mm"],
                14, -26, NA_DRAWN_TEXT_ACCENT_COLOR
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Lines Joining Each Start Corner to Its Moved Corner
        # Drawn straight through view.draw_line, so the two loops are converted
        # to draw space by hand — the same rule the live preview follows.
        # ------------------------------------------------------------
        def na_revise__draw_ghost_rungs(view, from_loop, to_loop, color)
            side_from = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(from_loop)
            side_to   = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(to_loop)

            view.line_stipple  = ''
            view.line_width    = 1
            view.drawing_color = color

            side_from.each_with_index do |point, index|
                view.draw_line(point, side_to[index]) if side_to[index]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The 2D Variant's Swept Strip, When the Record Came From an Edge
        # In an elevation the target face is edge-on and shades to nothing; the
        # strip the grabbed edge sweeps out is what the user watched while
        # dragging, so it is what the ghost sweeps too.
        # ------------------------------------------------------------
        def na_revise__draw_ghost_sweep(view, ghost, direction, world, cutting)
            edge = ghost[:edge_world]
            return false unless edge && edge.length == 2
            return false unless defined?(Na__InsertPrimatives::NA_PP2D_SWEEP_FILL)

            moved = edge.map { |point| Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, direction, world) }

            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledQuad(
                view,
                [edge[0], edge[1], moved[1], moved[0]],
                Na__InsertPrimatives::NA_PP2D_SWEEP_FILL,
                cutting ? self.class::NA_PP_QUAD_BORDER : Na__InsertPrimatives::NA_PP2D_SWEEP_BORDER
            )
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Ghost Occupies at a Distance, for the Extents
        # ------------------------------------------------------------
        def na_revise__ghost_points(ghost, value)
            loop_points = ghost[:loop]
            direction   = ghost[:direction]
            return [] if loop_points.nil? || loop_points.empty? || direction.nil?

            factor = ghost[:axis_factor].to_f
            factor = 1.0 if factor.abs < 0.0001
            world  = value.to_f / factor

            loop_points + loop_points.map do |point|
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, direction, world)
            end
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullRevise module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL REVISE MODULE
# =============================================================================
