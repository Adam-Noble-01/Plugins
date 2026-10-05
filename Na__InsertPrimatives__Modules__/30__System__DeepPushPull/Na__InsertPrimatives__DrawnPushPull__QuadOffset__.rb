# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL QUAD OFFSET
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull__QuadOffset__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnPushPullQuadOffset
# AUTHOR     : Noble Architecture
# PURPOSE    : With QUADS on, grab a quad line and push/pull a new ring off it,
#              then array it (*4) or divide the span (/7), mid-drag or after
# CREATED    : 2026
#
# DESCRIPTION:
# - The loop cut made the first ring on a run: drag the END face in with QUADS
#   on and a line appears. Every ring after that had to be measured from the
#   end again, because a quad line has no face to grab. This makes the line
#   itself the handle.
# - HOVER a face near one of its quad lines and the whole ring that line
#   belongs to lights up, all the way round the solid, with an arrow each way
#   along the run and how much run there is each way. The quad under the
#   cursor is shaded faintly, so it is clear which ring is meant.
# - CLICK AND DRAG along the run: a new ring follows the cursor, snapped to the
#   grid like every other distance here, with a dimension string from the
#   reference ring to the new one. Click or release to cut it.
# - TYPE while dragging or after placing, the way native Move takes a copy
#   array:
#     450          the offset, placed (mid-drag) or re-spaced (after)
#     *4  4x  x4   an array: rings at 1, 2, 3 and 4 times the offset
#     /7  7/       a divide: 7 equal spaces up to the offset
#     450*4 3000/7 both at once
#     -450         after placing: the same offset on the other side
#   Mid-drag, a count alone keeps the drag going so the array follows the
#   mouse; a distance places. After placing, every entry is a retype: the cut
#   is undone and made again at the new layout, and the ghost animates the
#   rings from where they were to where they now are.
# - The loop cut itself joins in. Dragging an end face in with QUADS on and
#   typing *4 (or typing it after the cut is placed) turns the cut into an
#   array from that face, through this same code.
#
# FORGIVING, NOT SILENT:
# - An array that would run off the end of the run is refused with the count
#   that fits ("*10 at 450 mm needs 4500 mm, the run has 2650 mm — *5 fits").
#   Rings are never dropped quietly. *0, a fractional count and an entry with
#   two operators each say what to type instead.
#
# COORDINATES: see the quad rings module header. Everything drawn is world;
# the commit re-reads the ring inside its operation.
#
# HOST CONTRACT — included by DrawnPushPullTool AFTER DrawnPushPullRevise, so
# its revise overrides sit in front of the push versions and fall back to them
# with super for every record that is not a quad offset.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnQuadRings__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnSlopePush__'
require_relative 'Na__InsertPrimatives__DrawnPushPull__Revise__'

module Na__InsertPrimatives

    module DrawnPushPullQuadOffset

        # -----------------------------------------------------------------------------
        # REGION | Constants
        # -----------------------------------------------------------------------------

        NA_QO_REFERENCE_WIDTH = 5                                             # <-- The ring being offset FROM, while hovered
        NA_QO_RING_WIDTH      = 3                                             # <-- Every ring about to be cut
        NA_QO_TICK_PX         = 7.0                                           # <-- Half-length of a dimension tick, on screen
        NA_QO_POINT_PX        = 8                                             # <-- Ring corner markers, on screen
        NA_QO_FACE_FILL       = Sketchup::Color.new(0, 140, 255, 40)          # <-- The quad under the cursor, faintly

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | State
        # -----------------------------------------------------------------------------

        # FUNCTION | Create Every Instance Variable This Mixin Relies On
        # ------------------------------------------------------------
        def na_qo__init_state
            @na_qo_hover         = nil                                        # <-- The ring offered under the cursor while idle
            @na_qo_hover_key     = nil                                        # <-- What the cached analysis was made from
            @na_qo_hover_scan    = nil                                        # <-- The cached analysis itself
            @na_qo_refusal       = nil                                        # <-- Why the quad line near the cursor cannot be offset
            @na_qo_target        = nil                                        # <-- The ring grabbed, while dragging
            @na_qo_count         = 1
            @na_qo_mode          = :array
            @na_qo_ghost_from    = nil                                        # <-- A loop cut being turned into an array: where it was
            @na_qo_face_line_key = nil
            @na_qo_face_has_line = false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drop the Grabbed Ring and Its Layout
        # ------------------------------------------------------------
        def na_qo__clear_grab
            @na_qo_target = nil
            @na_qo_count  = 1
            @na_qo_mode   = :array
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drop the Ring Offered Under the Cursor
        # ------------------------------------------------------------
        def na_qo__clear_hover
            @na_qo_hover   = nil
            @na_qo_refusal = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Cached Ring Analysis
        # Anything that changes the model can change how far a run reaches, so
        # every transaction drops it, ours included.
        # ------------------------------------------------------------
        def na_qo__forget_scan
            @na_qo_hover_key  = nil
            @na_qo_hover_scan = nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does This Tool Offer Quad Offsets?
        # Both cameras share the ring engine; the 2D tool supplies an edge pick.
        # ------------------------------------------------------------
        def na_qo__supported?
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Ring Grabbed and Being Dragged?
        # ------------------------------------------------------------
        def na_qo__active?
            @na_state == :picking_depth && !@na_qo_target.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Ring on Offer Under the Cursor?
        # ------------------------------------------------------------
        def na_qo__hovering?
            @na_state == :idle && !@na_qo_hover.nil? && na_drawn__quad_mode?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Revise Record a Quad Offset?
        # ------------------------------------------------------------
        def na_qo__record?(record)
            record.is_a?(Hash) && record[:kind] == :quad_offset
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is a Placed Quad Offset Waiting to Be Retyped?
        # ------------------------------------------------------------
        def na_qo__record_open?
            na_revise__available? && na_qo__record?(@na_revise_record)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Hover — Offer the Quad Line Beside the Cursor
        # -----------------------------------------------------------------------------

        # FUNCTION | Offer the Ring Through the Nearest Quad Line of the Hovered Face
        # ------------------------------------------------------------
        # Only with QUADS on, and only within NA_QUAD_RING_GRAB_PX of the line:
        # further in, the face is pushed exactly as before, so no gesture is lost.
        # Returns the offered ring, or nil.
        # ------------------------------------------------------------
        def na_qo__track_hover(view, x, y, face_target)
            na_qo__clear_hover
            return nil unless na_qo__supported? && na_drawn__quad_mode?
            return nil unless face_target && face_target[:face]

            face  = face_target[:face]
            xform = face_target[:transformation]
            edge  = Na__InsertPrimatives.Na__QuadRings__NearestQuadLine(view, face, xform, x, y)
            return nil unless edge

            analysis = na_qo__analysis_for(edge, face, xform)
            return nil unless analysis

            if analysis[:refusal]
                @na_qo_refusal = analysis[:refusal]
                return nil
            end

            @na_qo_hover = na_qo__build_target(analysis, face_target, view, x, y)
        rescue StandardError => error
            na_drawn__trace("quad line hover failed — #{error.message}")
            na_qo__clear_hover
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Ring Analysis for an Edge, Walked Once and Then Reused
        # Hovering asks on every mouse move; the ring and its rails only change
        # when the model does, and every transaction clears the cache.
        # ------------------------------------------------------------
        def na_qo__analysis_for(edge, face, xform)
            key = [
                edge.entityID, face.entityID,
                edge.start.position.to_a, edge.end.position.to_a, xform.to_a
            ]

            cached = @na_qo_hover_scan
            return cached if cached && key == @na_qo_hover_key && na_qo__analysis_live?(cached)

            @na_qo_hover_key  = key
            @na_qo_hover_scan = Na__InsertPrimatives.Na__QuadRings__Analyse(edge, xform, face)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is Every Entity a Cached Analysis Holds Still There?
        # ------------------------------------------------------------
        def na_qo__analysis_live?(analysis)
            return true if analysis[:refusal]

            analysis[:edges].all?(&:valid?) && analysis[:vertices].all?(&:valid?)
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Merge a Ring Analysis With Where It Was Picked
        # ------------------------------------------------------------
        # The pick supplies the path, the transformation and the instance
        # details the commit and the shared-definition warning read. The grab
        # point is the point of the quad line nearest the cursor: the drag is
        # measured from it and the dimension string starts on it. The probe is
        # the line's midpoint in the space it reports in, which is how the line
        # is found again after an undo.
        # ------------------------------------------------------------
        def na_qo__build_target(analysis, face_target, view, x, y)
            xform   = face_target[:transformation]
            edge    = analysis[:edge]
            start   = edge.start.position
            finish  = edge.end.position
            a_world = start.transform(xform)
            b_world = finish.transform(xform)
            grab    = Na__InsertPrimatives.Na__QuadRings__PointOnSegment(a_world, b_world, view.pickray(x, y))

            analysis.merge(
                :path           => face_target[:path],
                :transformation => xform,
                :depth          => face_target[:depth],
                :shared_count   => face_target[:shared_count],
                :locked         => face_target[:locked],
                :grab_world     => grab,
                :line_origin    => grab,
                :probe          => Geom::Point3d.linear_combination(0.5, start, 0.5, finish),
                :probe_dir      => (finish - start).normalize
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Face's Own Loop as the Ring, Offset Into the Solid
        # ------------------------------------------------------------
        # The loop cut's reference, for turning a loop cut into an array. The
        # dimension string starts on the loop nearest the anchor, and the drag
        # keeps measuring from the anchor it was already measuring from, so
        # nothing jumps when a mid-drag *4 hands the cut over to this mixin.
        # ------------------------------------------------------------
        def na_qo__face_target(face_target, direction_world, anchor_world)
            face     = face_target[:face]
            analysis = Na__InsertPrimatives.Na__QuadRings__AnalyseFace(face, face_target[:transformation], direction_world)
            return nil unless analysis

            analysis.merge(
                :path           => face_target[:path],
                :transformation => face_target[:transformation],
                :depth          => face_target[:depth],
                :shared_count   => face_target[:shared_count],
                :locked         => face_target[:locked],
                :grab_world     => Na__InsertPrimatives.Na__QuadRings__NearestOnRing(analysis[:ring_world], true, anchor_world),
                :line_origin    => anchor_world,
                :probe          => Na__InsertPrimatives.Na__SlopePush__InteriorPoint(face),
                :probe_normal   => face.normal
            )
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does the Hovered Face Carry a Quad Line? (Cached Per Face)
        # ------------------------------------------------------------
        def na_qo__face_has_quad_line?
            key = @na_pp_fingerprint
            return @na_qo_face_has_line if key && key == @na_qo_face_line_key

            @na_qo_face_line_key = key
            @na_qo_face_has_line =
                @na_pp_target ? Na__InsertPrimatives.Na__QuadRings__FaceHasQuadLine?(@na_pp_target[:face]) : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extra Lines for the Ordinary Face Hover Label
        # Says the feature is there while the cursor is on a face that has
        # something to offer, and says why when the line near it cannot move.
        # ------------------------------------------------------------
        def na_qo__face_hover_notes(quads)
            return [] unless quads && na_qo__supported?
            return ["quad line here, but #{@na_qo_refusal}"] if @na_qo_refusal
            return ['hover a quad line to offset it  (*4 array, /7 divide)'] if na_qo__face_has_quad_line?

            []
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Grab and Drag
        # -----------------------------------------------------------------------------

        # FUNCTION | Grab the Ring Under the Cursor, If One Is on Offer There
        # Asked fresh at the click rather than trusting the last hover, which
        # may be a frame behind the model. false leaves the face grab to run.
        # ------------------------------------------------------------
        def na_qo__pick_face(view, x, y)
            Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)
        end

        def na_qo__try_grab(view, x, y)
            return false if na_pps__active?
            return false unless na_qo__supported? && na_drawn__quad_mode?

            face_target = na_qo__pick_face(view, x, y)
            return false unless face_target && !face_target[:locked]

            ring = na_qo__track_hover(view, x, y, face_target)
            return false unless ring

            na_drawn__adopt_target(face_target)
            na_qo__begin_drag(ring, view, x, y)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enter the Drag With a Ring in Hand
        # ------------------------------------------------------------
        def na_qo__begin_drag(ring, view, x, y)
            @na_qo_target = ring
            @na_qo_count  = 1
            @na_qo_mode   = :array

            @na_ip.pick(view, x, y)
            @na_ip_origin.copy!(@na_ip)

            @na_point_a        = ring[:line_origin]
            @na_cursor_raw     = @na_point_a
            @na_cursor_snapped = @na_point_a

            na_drawn__clear_locks
            @na_state  = :picking_depth
            @na_size_d = 0.0
            @na_sign_d = 1.0

            @na_drag_press_active = true                                      # <-- Press-drag-release, as for a face
            @na_press_x           = @na_last_mouse_x
            @na_press_y           = @na_last_mouse_y

            na_qo__clear_hover
            na_drawn__warn_if_shared(ring)
            na_drawn__trace('quad line grabbed')
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Track the Offset Along the Run
        # The push tool's rule: nothing is re-picked mid-drag unless CTRL asks
        # for inference, and a frame that cannot be solved keeps the last good
        # distance. The travel is snapped, not the point.
        # ------------------------------------------------------------
        def na_qo__update_cursor(view, x, y)
            resolved = @na_ctrl_held ? na_drawn__input_point_position(view, x, y) : na_qo__ray_point(view, x, y)
            return false unless resolved

            @na_cursor_raw     = resolved
            @na_cursor_snapped = resolved
            na_qo__recalculate
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Project the Pick Ray onto the Run Through the Grab Point
        # ------------------------------------------------------------
        def na_qo__ray_point(view, x, y)
            target  = @na_qo_target
            ray     = view.pickray(x, y)
            closest = Geom.closest_points([target[:line_origin], target[:direction]], ray)
            return nil unless closest && closest[0]

            return closest[0] unless view.camera.perspective?

            na_drawn__point_in_front_of_ray?(ray, closest[0]) ? closest[0] : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measure the Drag Along the Run, Snapped
        # ------------------------------------------------------------
        def na_qo__recalculate
            return if na_drawn__locked?(:d)

            target    = @na_qo_target
            direction = target[:direction]
            travel    = (@na_cursor_raw - target[:line_origin]).dot(direction).to_f
            snapped   = na_drawn__snap_distance(travel).to_f

            @na_sign_d         = snapped < 0.0 ? -1.0 : 1.0
            @na_size_d         = snapped.abs
            @na_cursor_snapped = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(@na_cursor_raw, direction, snapped - travel)
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP: the Typed Distance, Then the Count, Then the Grab
        # ------------------------------------------------------------
        def na_qo__step_back(view)
            message =
                if na_drawn__release_last_lock
                    'Released the typed distance — back on the drag'
                elsif @na_qo_count > 1
                    @na_qo_count = 1
                    'Back to a single quad'
                else
                    na_drawn__reset_pick_state
                    nil
                end

            na_revise__notice(message) if message
            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y) if na_qo__active?
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Double Click on a Grabbed Ring
        # With no drag behind it there is nothing to place, and a push's repeat
        # has no meaning for a ring (its run has no "out"). So it says what to do.
        # ------------------------------------------------------------
        def na_qo__double_click(view, x, y)
            travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs

            if travelled_px < Na__InsertPrimatives::DrawnToolShared::NA_DRAWN_DRAG_MIN_PX
                na_revise__notice('Drag along the run, or type a distance — *4 arrays it, /7 divides it')
            else
                na_drawn__update_cursor(view, x, y)
                na_qo__commit(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Arrow Keys Have Nothing to Lock Here
        # ------------------------------------------------------------
        def na_qo__refuse_axis_lock
            UI.beep
            na_revise__notice('A quad offset slides along its own run — the arrow keys have nothing to lock')
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | No Axis Fragment in the Status Line While a Ring Is Grabbed
        # A lock left on for pushes is kept for them, and is not claimed here.
        # ------------------------------------------------------------
        def na_drawn__axis_description
            return '' if na_qo__active?

            super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Layout and Fit
        # -----------------------------------------------------------------------------

        # FUNCTION | The Layout the Live Drag Describes
        # distance is signed along the ring's run direction, in world inches.
        # ------------------------------------------------------------
        def na_qo__live_layout
            { :distance => na_drawn__signed_d, :count => @na_qo_count, :mode => @na_qo_mode }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Signed Offset a Layout Places
        # ------------------------------------------------------------
        def na_qo__offsets(layout)
            Na__InsertPrimatives.Na__QuadRings__Offsets(layout[:distance], layout[:count], layout[:mode])
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far the Furthest Ring of a Layout Goes
        # ------------------------------------------------------------
        def na_qo__furthest(layout)
            distance = layout[:distance].to_f.abs
            layout[:mode] == :divide ? distance : distance * [layout[:count].to_i, 1].max
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Run Left on the Side a Layout Goes, or nil
        # ------------------------------------------------------------
        def na_qo__reach_for(target, layout)
            layout[:distance].to_f < 0.0 ? target[:reach_neg] : target[:reach_pos]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Why a Layout Cannot Be Cut Here, or nil When It Can
        # ------------------------------------------------------------
        def na_qo__fit_problem(target, layout)
            distance = layout[:distance].to_f
            return nil unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(distance)

            spacing = Na__InsertPrimatives.Na__QuadRings__Spacing(distance, layout[:count], layout[:mode])

            if spacing < NA_EDGE_LOOP_MIN_TRAVEL
                return "the rings would be #{Na__InsertPrimatives.Na__QuadRings__MmText(spacing)} mm apart — too close to cut"
            end

            reach = na_qo__reach_for(target, layout)
            return nil if reach.nil?

            furthest = na_qo__furthest(layout)
            return nil if furthest < reach - NA_EDGE_LOOP_MIN_TRAVEL

            na_qo__fit_advice(target, layout, reach, spacing, furthest)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say What Does Fit, Not Just That This Does Not
        # ------------------------------------------------------------
        def na_qo__fit_advice(target, layout, reach, spacing, furthest)
            reach_text = Na__InsertPrimatives.Na__QuadRings__MmText(reach)

            if reach <= NA_EDGE_LOOP_MIN_TRAVEL
                return 'a quad cut from a face runs into the solid — drag or type it inward, no minus' if target[:kind] == :face

                return 'the run stops at this quad line on that side — offset the other way'
            end

            count = layout[:count].to_i

            if layout[:mode] == :array && count > 1
                fits = ((reach - NA_EDGE_LOOP_MIN_TRAVEL) / spacing).floor

                if fits >= 1
                    return "*#{count} at #{Na__InsertPrimatives.Na__QuadRings__MmText(spacing)} mm needs " \
                           "#{Na__InsertPrimatives.Na__QuadRings__MmText(furthest)} mm, the run has #{reach_text} mm — *#{fits} fits"
                end
            end

            "#{Na__InsertPrimatives.Na__QuadRings__MmText(furthest)} mm is past the end of the run — it has #{reach_text} mm"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Refuse a Typed Layout That Will Not Fit, Before Anything Is Undone
        # ------------------------------------------------------------
        def na_qo__check_fit!(target, layout)
            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(layout[:distance])
                raise ArgumentError, 'there is no offset to array yet — type a distance first, e.g. 450*4'
            end

            problem = na_qo__fit_problem(target, layout)
            raise ArgumentError, problem if problem

            layout
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Layout in Words: "450 mm", "4 × 450 mm", "3000 mm ÷ 7"
        # ------------------------------------------------------------
        def na_qo__layout_text(layout)
            distance = Na__InsertPrimatives.Na__QuadRings__MmText(layout[:distance])
            count    = layout[:count].to_i

            return "#{distance} mm" if count <= 1
            return "#{distance} mm ÷ #{count}" if layout[:mode] == :divide

            "#{count} × #{distance} mm"
        rescue StandardError
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Headline for the Preview Card
        # ------------------------------------------------------------
        def na_qo__layout_headline(layout)
            count   = layout[:count].to_i
            spacing = Na__InsertPrimatives.Na__QuadRings__Spacing(layout[:distance], count, layout[:mode])
            text    = Na__InsertPrimatives.Na__QuadRings__MmText(layout[:distance])
            gap     = Na__InsertPrimatives.Na__QuadRings__MmText(spacing)
            total   = Na__InsertPrimatives.Na__QuadRings__MmText(na_qo__furthest(layout))

            return "Quad offset #{text} mm" if count <= 1
            return "Divide #{text} mm ÷ #{count} = #{gap} mm each" if layout[:mode] == :divide

            "Array #{count} × #{gap} mm = #{total} mm"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | A Typed Entry While a Ring Is Being Dragged
        # ------------------------------------------------------------
        # A count alone sets the layout and the drag goes on, so the array can
        # be sized by eye. A distance places, exactly as it does for a push,
        # and a leading +/- is the usual arithmetic against the live number.
        # ------------------------------------------------------------
        def na_qo__handle_vcb_text(text, view)
            entry = Na__InsertPrimatives.Na__QuadRings__ParseEntry(text)

            if entry[:count]
                @na_qo_count = entry[:count]
                @na_qo_mode  = entry[:mode]
            end

            unless entry[:distance]
                na_qo__notice_layout
                return true
            end

            distances = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst([entry[:distance]], [@na_size_d])
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(distances, ['Offset'])

            @na_size_d = distances[0]
            na_drawn__lock_slot(:d)
            na_qo__commit(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say What a Count Typed Mid-Drag Has Done
        # ------------------------------------------------------------
        def na_qo__notice_layout
            count = @na_qo_count.to_i

            message =
                if count <= 1
                    'Single quad — drag the offset, or type it'
                elsif @na_qo_mode == :divide
                    "Divide into #{count} — drag the whole span, click to place, or type it"
                else
                    "Array of #{count} — drag the spacing, click to place, or type it"
                end

            na_revise__notice(message)
        end
        # ---------------------------------------------------------------

        # FUNCTION | *4 or /7 Typed While a Loop Cut Is Being Dragged
        # ------------------------------------------------------------
        # The loop cut hands over to this mixin: the face's own loop becomes the
        # ring, offset into the solid, and the drag carries on at the distance
        # it had reached. Refused, with the fix, when the drag is not a cut.
        # ------------------------------------------------------------
        def na_qo__convert_cut_drag(text, view)
            if na_pps__active? && @na_pps_targets.length > 1
                raise ArgumentError, 'Array one edge loop at a time — select a single face or grab a loop edge'
            end

            unless na_drawn__quad_mode?
                raise ArgumentError, '*4 and /7 array QUAD cuts — press TAB for QUADS, then drag into the face'
            end

            travel = na_drawn__world_travel_distance
            if travel > NA_EDGE_LOOP_MIN_TRAVEL
                raise ArgumentError, '*4 and /7 array quad cuts, and this drag is a push — drag INTO the face to cut'
            end

            entry       = Na__InsertPrimatives.Na__QuadRings__ParseEntry(text)
            face_target = @na_pp_target
            direction   = na_drawn__travel_direction
            raise ArgumentError, 'grab a face first' unless face_target && face_target[:face] && direction

            ring = na_qo__face_target(face_target, direction.reverse, @na_point_a)
            raise ArgumentError, 'this face could not be read as a ring to array from' unless ring

            if ring[:reach_pos] && ring[:reach_pos] <= NA_EDGE_LOOP_MIN_TRAVEL
                raise ArgumentError, 'the faces round this one do not run back from it — there is nothing to array along'
            end

            @na_qo_target = ring
            @na_qo_count  = entry[:count] || 1
            @na_qo_mode   = entry[:mode]  || :array
            @na_size_d    = travel.abs
            @na_sign_d    = 1.0
            na_drawn__clear_locks

            unless entry[:distance]
                na_qo__notice_layout
                return true
            end

            distances = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst([entry[:distance]], [@na_size_d])
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(distances, ['Offset'])

            @na_size_d = distances[0]
            na_drawn__lock_slot(:d)
            na_qo__commit(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Measurements Box While Dragging, or With a Quad Offset Placed
        # ------------------------------------------------------------
        def na_qo__vcb_label_and_value
            layout = na_qo__active? ? na_qo__live_layout : @na_revise_record[:value]
            count  = layout[:count].to_i

            label =
                if count <= 1                   then 'Quad offset'
                elsif layout[:mode] == :divide  then "Quad span /#{count}"
                else                                 "Quad spacing *#{count}"
                end

            [label, Na__InsertPrimatives.Na__QuadRings__MmText(layout[:distance])]
        rescue StandardError
            ['Quad offset', '']
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Commit
        # -----------------------------------------------------------------------------

        # FUNCTION | Cut the Ring(s) the Layout Describes
        # ------------------------------------------------------------
        # One operation, inside the ring's own editing context, so the whole
        # array is one Ctrl+Z. A layout that does not fit is refused with the
        # grab kept, so the user can type the count that does. A cut where no
        # ring landed at all is rolled back rather than left as an empty step.
        # ------------------------------------------------------------
        def na_qo__commit(view)
            target = @na_qo_target

            unless na_qo__target_valid?(target)
                UI.beep
                na_revise__notice('That quad line is no longer in the model')
                na_drawn__reset_pick_state
                return false
            end

            layout = na_qo__live_layout

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(layout[:distance])
                UI.beep
                na_revise__notice('No offset yet — drag along the run or type a distance')
                return false
            end

            problem = na_qo__fit_problem(target, layout)
            if problem
                UI.beep
                na_revise__notice("Not placed — #{problem}")
                return false
            end

            model     = Sketchup.active_model
            user_path = model.respond_to?(:active_path) ? model.active_path : nil
            offsets   = na_qo__offsets(layout)
            stats     = nil

            result = Na__InsertPrimatives.Na__DeepPick__ExecuteInContext(model, target[:path], na_qo__operation_name(layout)) do |entered|
                stats = na_qo__stitch_rings(model, target, entered, offsets)
                raise 'no ring landed on the faces along this run' if stats[:kept].to_i.zero?
            end

            na_qo__forget_scan

            unless result[:success]
                UI.beep
                na_revise__notice("Quad offset not made — #{result[:error]}")
                na_qo__report_failure(target, layout, stats, result[:error])
                na_revise__forget
                na_drawn__reset_pick_state
                return false
            end

            na_qo__capture(target, layout, user_path)
            na_qo__log(target, layout, offsets, stats, result[:entered])

            if stats[:misplaced] || stats[:swept].to_i > 0
                UI.beep
                na_revise__notice('Quad offset placed, but part of it bounded nothing and was swept off — see the console')
            end

            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Ring Still in the Model?
        # ------------------------------------------------------------
        def na_qo__target_valid?(target)
            return false unless target

            holder = target[:kind] == :face ? target[:face] : target[:edge]
            return false unless holder && holder.valid?

            target[:vertices].all?(&:valid?)
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Undo Step's Name
        # ------------------------------------------------------------
        def na_qo__operation_name(layout)
            count = layout[:count].to_i
            return 'Deep Push Pull (Quad Offset)' if count <= 1
            return "Deep Push Pull (Quad Divide /#{count})" if layout[:mode] == :divide

            "Deep Push Pull (Quad Array x#{count})"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Stitch Every Ring, Read Fresh Inside the Operation
        # ------------------------------------------------------------
        # The ring's corners are re-read HERE, after the context was entered,
        # so they are in the space the collection is accepting now: global when
        # entered (and in the user's own open context), local only if the open
        # failed, when the pick's transformation still maps them. Each ring is
        # the reference moved along the run in WORLD, then brought back into
        # that space, so an instance scale can never stretch the spacing.
        # ------------------------------------------------------------
        def na_qo__stitch_rings(model, target, entered, offsets)
            xform   = entered ? Geom::Transformation.new : target[:transformation]
            inverse = xform.inverse
            holder  = target[:kind] == :face ? target[:face] : target[:edge]
            raise 'the quad line is no longer in the model' unless holder && holder.valid?

            parent   = holder.parent
            entities = parent.respond_to?(:entities) ? parent.entities : model.active_entities
            base     = target[:vertices].map { |vertex| vertex.position.transform(xform) }
            totals   = { :kept => 0, :swept => 0, :faces_removed => 0, :misplaced => false, :rings => 0 }
            build    = nil

            offsets.each do |offset|
                points = base.map do |point|
                    Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, target[:direction], offset).transform(inverse)
                end

                build ||= Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, points.first)
                stats   = Na__InsertPrimatives.Na__QuadRings__Stitch(entities, points, target[:closed], build)

                totals[:kept]          += stats[:kept].to_i
                totals[:swept]         += stats[:swept].to_i
                totals[:faces_removed] += stats[:faces_removed].to_i
                totals[:misplaced]    ||= stats[:misplaced] ? true : false
                totals[:rings]         += 1 if stats[:kept].to_i > 0
            end

            totals
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Revise — Capture, Re-Acquire, Rebuild
        # -----------------------------------------------------------------------------

        # FUNCTION | Arm the Retype With Everything a Rebuild Reads
        # ------------------------------------------------------------
        # The value is the LAYOUT, not a number: a retype can change the offset,
        # the count or both. During a rebuild the ghost carries where the rings
        # were (the record being rebuilt) and where they now go, so the replay
        # can sweep every ring from one to the other.
        # ------------------------------------------------------------
        def na_qo__capture(target, layout, user_path)
            holder   = target[:kind] == :face ? target[:face] : target[:edge]
            entities = na_revise__live_entities(holder, nil)
            return na_revise__forget unless entities

            replaying    = @na_revise_replaying
            to_offsets   = na_qo__offsets(layout)
            from_offsets =
                if    na_qo__record?(replaying) then na_qo__offsets(replaying[:value])
                elsif @na_qo_ghost_from         then @na_qo_ghost_from
                else                                 to_offsets
                end

            anchor =
                if    na_qo__record?(replaying) then replaying[:anchor_sign].to_f
                elsif replaying                 then 1.0                     # <-- A loop cut turned into an array: into the solid is forward
                else                                 layout[:distance].to_f < 0.0 ? -1.0 : 1.0
                end

            value = { :distance => layout[:distance].to_f, :count => layout[:count].to_i, :mode => layout[:mode] }

            na_revise__arm({
                :kind        => :quad_offset,
                :target      => target,
                :entities    => entities,
                :user_path   => user_path,
                :counts      => [[entities, na_revise__entity_count(entities)]],
                :ops         => 1,
                :value       => value,
                :anchor_sign => anchor,
                :ghost       => {
                    :kind        => :quad_offset,
                    :ring        => target[:ring_world].map { |point| point.clone },
                    :closed      => target[:closed],
                    :direction   => target[:direction].clone,
                    :anchor      => target[:grab_world].clone,
                    :from        => from_offsets,
                    :to          => to_offsets,
                    :from_layout => replaying ? replaying[:value] : value,
                    :to_layout   => value
                }
            })
        rescue StandardError => error
            na_drawn__trace("quad offset retype not armed — #{error.message}")
            na_revise__forget
        end
        # ---------------------------------------------------------------

        # FUNCTION | Find the Reference Ring Again Where the Undo Left It
        # ------------------------------------------------------------
        def na_revise__reacquire(record)
            return super unless na_qo__record?(record)

            target   = record[:target]
            holder   = target[:kind] == :face ? target[:face] : target[:edge]
            entities = na_revise__live_entities(holder, record[:entities])
            return nil unless entities

            xform = target[:transformation]

            analysis =
                if target[:kind] == :face
                    face = na_qo__face_again(entities, target)
                    face ? Na__InsertPrimatives.Na__QuadRings__AnalyseFace(face, xform, target[:direction]) : nil
                else
                    edge = na_qo__edge_again(entities, target)
                    edge ? Na__InsertPrimatives.Na__QuadRings__Analyse(edge, xform, nil, target[:direction_rep]) : nil
                end

            return nil if analysis.nil? || analysis[:refusal]

            target.merge(analysis)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Grabbed Quad Line Again: the Object, or Its Midpoint
        # ------------------------------------------------------------
        def na_qo__edge_again(entities, target)
            return target[:edge] if na_qo__edge_at_probe?(target[:edge], target)

            entities.grep(Sketchup::Edge).find { |candidate| na_qo__edge_at_probe?(candidate, target) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does an Edge Sit Where the Grabbed Line Sat, Pointing the Same Way?
        # ------------------------------------------------------------
        def na_qo__edge_at_probe?(edge, target)
            return false unless edge && edge.valid?

            start  = edge.start.position
            finish = edge.end.position
            middle = Geom::Point3d.linear_combination(0.5, start, 0.5, finish)
            return false unless middle.distance(target[:probe]) < NA_QUAD_RING_PROBE_TOL

            along = finish - start
            along.length > 0.0 && along.parallel?(target[:probe_dir])
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Face a Face-Loop Ring Came From, Again
        # ------------------------------------------------------------
        def na_qo__face_again(entities, target)
            probe  = target[:probe]
            normal = target[:probe_normal]
            face   = target[:face]
            return nil unless probe

            return face if face && face.valid? && face.classify_point(probe) == Sketchup::Face::PointInside

            entities.grep(Sketchup::Face).find do |candidate|
                candidate.valid? &&
                    (normal.nil? || candidate.normal.samedirection?(normal)) &&
                    candidate.classify_point(probe) == Sketchup::Face::PointInside
            end
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Commit Again at a New Layout
        # ------------------------------------------------------------
        # A quad record rebuilds from its own ring. A loop cut being arrayed
        # (a push record retyped with *N or /N) rebuilds from its face, which
        # the push re-acquire has just found again.
        # ------------------------------------------------------------
        def na_revise__rebuild(record, target, value, view)
            return super unless na_qo__record?(record) || value.is_a?(Hash)

            ring = na_qo__record?(record) ? target : na_qo__target_from_cut(record, target)
            return false unless ring

            placed = false
            na_qo__wearing(record, ring, value) { placed = na_qo__commit(view) }
            placed ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Wear the Layout a Rebuild Is Made At
        # ------------------------------------------------------------
        def na_qo__wearing(record, ring, layout)
            @na_revise_replaying = record
            @na_qo_target        = ring
            @na_qo_count         = [layout[:count].to_i, 1].max
            @na_qo_mode          = layout[:mode] == :divide ? :divide : :array
            @na_size_d           = layout[:distance].to_f.abs
            @na_sign_d           = layout[:distance].to_f < 0.0 ? -1.0 : 1.0
            @na_qo_ghost_from    = na_qo__record?(record) ? nil : [na_qo__cut_distance(record, ring)]

            yield
        ensure
            @na_revise_replaying = nil
            @na_qo_ghost_from    = nil
            na_qo__clear_grab
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Placed Loop Cut as a Face-Loop Ring
        # ------------------------------------------------------------
        # The cut's recorded offset is in the face's own space and points into
        # the solid, which is exactly the run the array goes along. The string
        # is anchored on the side of the loop nearest the camera, where it can
        # be seen, since a retype has no cursor to anchor it to.
        # ------------------------------------------------------------
        def na_qo__target_from_cut(record, face_target)
            return nil unless record && record[:cut]
            return nil unless face_target && face_target[:face] && face_target[:face].valid?

            offset = record[:offset]
            return nil unless offset && offset.length > 0.0

            direction = Na__InsertPrimatives.Na__QuadRings__WorldDirection(offset, face_target[:transformation])
            return nil unless direction

            model  = Sketchup.active_model
            eye    = model ? model.active_view.camera.eye : nil
            loop   = Na__InsertPrimatives.Na__DeepPick__WorldOuterLoop(face_target[:face], face_target[:transformation])
            anchor = eye ? Na__InsertPrimatives.Na__QuadRings__NearestOnRing(loop, true, eye) : loop.first

            na_qo__face_target(face_target, direction, anchor)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far a Placed Loop Cut Was Inset, in World Inches
        # ------------------------------------------------------------
        def na_qo__cut_distance(record, ring)
            offset = record[:offset]
            return 0.0 unless offset && ring

            origin = Geom::Point3d.new(0, 0, 0)
            (origin.offset(offset).transform(ring[:transformation]) - origin.transform(ring[:transformation])).length.to_f
        rescue StandardError
            0.0
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Revise — What a Retype Reads and Says
        # -----------------------------------------------------------------------------

        # FUNCTION | Read a Retype, for a Quad Offset or a Loop Cut Being Arrayed
        # ------------------------------------------------------------
        def na_revise__parse_retype(text, record)
            return na_qo__parse_record_retype(text, record) if na_qo__record?(record)
            return super unless Na__InsertPrimatives.Na__QuadRings__ArrayEntry?(text)

            na_qo__parse_cut_retype(text, record)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Retype of a Placed Quad Offset
        # What is typed replaces what it names and keeps the rest: 600 re-spaces
        # an array of 4 as an array of 4, *6 keeps the spacing, /7 keeps the
        # span. The sign names the side, measured from the side first dragged.
        # ------------------------------------------------------------
        def na_qo__parse_record_retype(text, record)
            entry   = Na__InsertPrimatives.Na__QuadRings__ParseEntry(text)
            current = record[:value]

            layout = {
                :distance => entry[:distance] ? na_qo__signed_retype(entry[:distance], record[:anchor_sign]) : current[:distance].to_f,
                :count    => entry[:count] || current[:count],
                :mode     => entry[:mode]  || current[:mode]
            }

            na_qo__check_fit!(record[:target], layout)
        end
        # ---------------------------------------------------------------

        # FUNCTION | *N or /N Typed After a Loop Cut or a Push
        # ------------------------------------------------------------
        def na_qo__parse_cut_retype(text, record)
            unless record[:cut]
                raise ArgumentError, '*4 and /7 repeat quad cuts, and this was a push — hover a quad line, or drag INTO a face with QUADS on'
            end

            entry = Na__InsertPrimatives.Na__QuadRings__ParseEntry(text)
            ring  = na_qo__target_from_cut(record, record[:target])
            raise ArgumentError, 'that loop cut could not be read again to array it' unless ring

            layout = {
                :distance => entry[:distance] ? na_qo__signed_retype(entry[:distance], 1.0) : na_qo__cut_distance(record, ring),
                :count    => entry[:count] || 1,
                :mode     => entry[:mode]  || :array
            }

            na_qo__check_fit!(ring, layout)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Distance as a Signed Offset After Placing
        # ------------------------------------------------------------
        def na_qo__signed_retype(token, anchor_sign)
            sign, magnitude = token

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(magnitude)
                raise ArgumentError, "offset would be #{Na__InsertPrimatives.Na__DrawnFormat__Mm(magnitude)}mm — must be positive"
            end

            magnitude.to_f.abs * (sign == :minus ? -1.0 : 1.0) * (anchor_sign.to_f < 0.0 ? -1.0 : 1.0)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Layout Change Animates Every Ring, Not One Number
        # The ghost holds both layouts, so the engine is simply run from 0 to 1.
        # ------------------------------------------------------------
        def na_revise__animate_change(record, from_value, to_value)
            return super unless from_value.is_a?(Hash) || to_value.is_a?(Hash)

            na_revise__animate(record, 0.0, 1.0)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Layout in the Retype Notice
        # ------------------------------------------------------------
        def na_revise__value_label(value)
            return na_qo__layout_text(value) if value.is_a?(Hash)

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | How a Placed Quad Offset Reads in the Status Bar
        # ------------------------------------------------------------
        def na_revise__placed_label(record)
            return na_qo__layout_text(record[:value]) if na_qo__record?(record)

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Else a Retype Can Say Right Now
        # ------------------------------------------------------------
        def na_revise__sign_hint
            record = @na_revise_record
            return ' (- flips side, *N array, /N divide)' if na_qo__record?(record)
            return ' (- reverses, *N or /N arrays the cut)' if record && record[:cut] && na_qo__supported?

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Transaction Can Move a Run's End — Drop the Cached Ring
        # ------------------------------------------------------------
        def na_revise__on_transaction(kind)
            na_qo__forget_scan
            super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Every Point the Preview Occupies, for the Draw Extents
        # ------------------------------------------------------------
        def na_qo__preview_points
            target = na_qo__active? ? @na_qo_target : @na_qo_hover
            return [] unless target

            points = target[:ring_world].dup
            return points unless na_qo__active?

            layout = na_qo__live_layout
            return points unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(layout[:distance])

            furthest = na_qo__rings_at(target, [na_qo__offsets(layout).last]).first
            furthest ? points + furthest : points
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Reference Ring Moved to Each Offset
        # ------------------------------------------------------------
        def na_qo__rings_at(target, offsets)
            offsets.map do |offset|
                target[:ring_world].map do |point|
                    Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, target[:direction], offset)
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw a Ring Closed, or a Chain Open
        # ------------------------------------------------------------
        def na_qo__draw_ring(view, points, closed, colour, width)
            return unless points && points.length >= 2

            if closed
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, points, colour, width)
                return
            end

            view.line_stipple  = ''
            view.line_width    = width
            view.drawing_color = colour
            view.draw(GL_LINE_STRIP, Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(points))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Hover: the Ring Being Referenced, All the Way Round
        # ------------------------------------------------------------
        # The ring is drawn heavy in the quad colour with its corners marked,
        # the quad under the cursor is shaded faintly so the side is clear, and
        # an arrow each way along the run carries how much run there is.
        # ------------------------------------------------------------
        def na_qo__draw_hover(view)
            ring = @na_qo_hover
            return unless ring

            colours = self.class

            unless @na_pp_triangles.nil? || @na_pp_triangles.empty?
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, @na_pp_triangles, NA_QO_FACE_FILL)
            end

            na_qo__draw_ring(view, ring[:ring_world], ring[:closed], colours::NA_PP_QUAD_BORDER, NA_QO_REFERENCE_WIDTH)

            begin
                view.draw_points(ring[:ring_world], NA_QO_POINT_PX, 2, colours::NA_PP_QUAD_BORDER)
            rescue StandardError
                nil
            end

            na_qo__draw_run_arrows(view, ring)

            edges = ring[:edges].length
            shape = ring[:closed] ? "#{edges}-edge ring" : "#{edges}-edge line"

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, ring[:grab_world],
                [
                    "QUAD LINE — #{shape}",
                    'drag along the run to offset a new quad',
                    'then type *4 to array, /4 to divide',
                    Na__InsertPrimatives.Na__DeepPick__PathLabel(ring)
                ],
                14, 18
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Arrow Each Way Along the Run, Each Saying How Far It Goes
        # A side with no run left gets no arrow, so a quad line at the very end
        # of a run points only the one way it can go.
        # ------------------------------------------------------------
        def na_qo__draw_run_arrows(view, ring)
            origin    = ring[:grab_world]
            direction = ring[:direction]
            colour    = self.class::NA_PP_QUAD_BORDER

            [[direction, ring[:reach_pos]], [direction.reverse, ring[:reach_neg]]].each do |heading, reach|
                next if reach && reach <= NA_EDGE_LOOP_MIN_TRAVEL

                Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(view, origin, heading, colour)
                next unless reach

                tip = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(
                    origin, heading, view.pixels_to_model(NA_DRAWN_ARROW_PIXELS + 8.0, origin).to_f
                )
                Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                    view, tip, ["#{Na__InsertPrimatives.Na__QuadRings__MmText(reach)} mm"], 4, -8, NA_DRAWN_TEXT_ACCENT_COLOR
                )
            end
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drag: the Reference, the New Ring(s), and the Spacing
        # ------------------------------------------------------------
        def na_qo__draw_preview(view)
            target = @na_qo_target
            return unless target

            colours = self.class
            layout  = na_qo__live_layout

            na_qo__draw_ring(view, target[:ring_world], target[:closed], colours::NA_PP_HOVER_BORDER, NA_QO_RING_WIDTH)

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(layout[:distance])
                na_qo__draw_run_arrows(view, target)
                Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                    view, target[:grab_world],
                    [na_qo__layout_headline(layout), 'drag along the run, or type a distance'],
                    14, 18
                )
                return
            end

            problem = na_qo__fit_problem(target, layout)
            colour  = problem ? NA_DRAWN_REFUSED_BORDER_CLR : colours::NA_PP_QUAD_BORDER
            offsets = na_qo__offsets(layout)
            rings   = na_qo__rings_at(target, offsets)

            na_qo__draw_rungs(view, target[:ring_world], rings.last, colour)
            rings.each { |ring| na_qo__draw_ring(view, ring, target[:closed], colour, NA_QO_RING_WIDTH) }

            direction = layout[:distance].to_f < 0.0 ? target[:direction].reverse : target[:direction]
            Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(view, target[:grab_world], direction, colour)

            na_qo__draw_dimension_string(
                view, target[:grab_world], target[:direction], offsets,
                problem ? NA_DRAWN_REFUSED_TEXT_COLOR : NA_DRAWN_TEXT_ACCENT_COLOR
            )

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view,
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(target[:grab_world], target[:direction], offsets.last),
                na_qo__summary_lines(target, layout, problem),
                14, -26,
                problem ? NA_DRAWN_REFUSED_TEXT_COLOR : nil
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Lines on the Preview Card
        # ------------------------------------------------------------
        def na_qo__summary_lines(target, layout, problem)
            lines = [na_qo__layout_headline(layout)]

            if problem
                lines << "NOT PLACEABLE — #{problem}"
            else
                reach = na_qo__reach_for(target, layout)
                if reach
                    left = reach - na_qo__furthest(layout)
                    lines << "#{Na__InsertPrimatives.Na__QuadRings__MmText(left)} mm of run left beyond it"
                end
            end

            lines << 'type *4 to array  ·  /4 to divide' if layout[:count].to_i <= 1
            lines
        end
        # ---------------------------------------------------------------

        # FUNCTION | Lines From Each Reference Corner to the Furthest Ring
        # The swept strip the new rings divide, drawn thin like a push's rungs.
        # ------------------------------------------------------------
        def na_qo__draw_rungs(view, from_ring, to_ring, colour)
            return unless from_ring && to_ring

            side_from = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(from_ring)
            side_to   = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(to_ring)

            view.line_stipple  = ''
            view.line_width    = 1
            view.drawing_color = colour

            side_from.each_with_index do |point, index|
                view.draw_line(point, side_to[index]) if side_to[index]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Dimension String Along the Run, a Tick at Every Ring
        # ------------------------------------------------------------
        # From the grab point on the reference ring to the furthest new one,
        # with every span labelled. Labels that would land on top of each other
        # are thinned out by the push tool's own screen-slot rule, so a dense
        # divide still reads.
        # ------------------------------------------------------------
        def na_qo__draw_dimension_string(view, origin, direction, offsets, colour)
            stations = [0.0] + offsets
            points   = stations.map { |station| Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(origin, direction, station) }
            camera   = view.camera.direction
            side     = direction.cross(camera)
            side     = direction.axes[0] if side.length <= 0.0
            side.normalize!

            view.line_stipple  = ''
            view.line_width    = 1
            view.drawing_color = colour
            view.draw_line(points.first, points.last)

            points.each do |point|
                tick = view.pixels_to_model(NA_QO_TICK_PX, point).to_f
                view.draw_line(
                    Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, side, tick),
                    Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, side, -tick)
                )
            end

            placed = []

            (1...points.length).each do |index|
                next unless na_drawn__claim_label_slot(view, points[index - 1], points[index], placed)

                gap = stations[index] - stations[index - 1]
                Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                    view, points[index - 1], points[index],
                    Na__InsertPrimatives.Na__QuadRings__MmText(gap), colour
                )
            end
        rescue StandardError
            nil                                                               # <-- Never let a dimension kill the draw pass
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Retype Ghost: Every Ring Sweeping From Old to New
        # ------------------------------------------------------------
        # progress runs 0 to 1. Ring i travels from its old offset to its new
        # one; a ring the new layout adds grows out of the last old ring, and a
        # ring it drops slides onto the last new one, so a change of count reads
        # as rings fanning out or folding in rather than blinking.
        # ------------------------------------------------------------
        def na_revise__draw_ghost(view, ghost, value, from_value, to_value)
            return super unless ghost.is_a?(Hash) && ghost[:kind] == :quad_offset

            colours = self.class
            offsets = na_qo__ghost_offsets(ghost, value)
            return false if offsets.empty?

            rings = offsets.map do |offset|
                ghost[:ring].map { |point| Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, ghost[:direction], offset) }
            end

            furthest = offsets.each_with_index.max_by { |offset, _index| offset.abs }[1]

            na_qo__draw_ring(view, ghost[:ring], ghost[:closed], colours::NA_PP_HOVER_BORDER, 2)
            na_qo__draw_rungs(view, ghost[:ring], rings[furthest], colours::NA_PP_QUAD_BORDER)
            rings.each { |ring| na_qo__draw_ring(view, ring, ghost[:closed], colours::NA_PP_QUAD_BORDER, NA_QO_RING_WIDTH) }
            na_qo__draw_dimension_string(view, ghost[:anchor], ghost[:direction], offsets.sort_by(&:abs), NA_DRAWN_TEXT_ACCENT_COLOR)

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view,
                Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(ghost[:anchor], ghost[:direction], offsets[furthest]),
                ["Quad #{na_revise__value_label(ghost[:from_layout])} → #{na_revise__value_label(ghost[:to_layout])}"],
                14, -26, NA_DRAWN_TEXT_ACCENT_COLOR
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where Every Ghost Ring Is at a Point in the Sweep
        # ------------------------------------------------------------
        def na_qo__ghost_offsets(ghost, progress)
            from  = ghost[:from] || []
            to    = ghost[:to]   || []
            count = [from.length, to.length].max
            t     = progress.to_f

            (0...count).map do |index|
                start  = from[index] || from.last || 0.0
                finish = to[index]   || to.last   || 0.0
                start + ((finish - start) * t)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Ghost Occupies, for the Extents
        # ------------------------------------------------------------
        def na_revise__ghost_points(ghost, value)
            return super unless ghost.is_a?(Hash) && ghost[:kind] == :quad_offset

            offsets = na_qo__ghost_offsets(ghost, value)
            return ghost[:ring] if offsets.empty?

            furthest = offsets.max_by(&:abs)
            ghost[:ring] + ghost[:ring].map { |point| Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(point, ghost[:direction], furthest) }
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status Bar and Console
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Line, Hovering or Dragging a Ring
        # ------------------------------------------------------------
        def na_qo__status_detail
            if na_qo__active?
                layout = na_qo__live_layout

                unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(layout[:distance])
                    return 'Quad line grabbed — drag along the run, or type a distance  (*4 array, /7 divide)'
                end

                problem = na_qo__fit_problem(@na_qo_target, layout)
                text    = na_qo__layout_text(layout)
                if problem
                    freed = na_drawn__locked?(:d) ? '  (BKSP frees the drag)' : ''
                    return "Quad offset #{text} — NOT PLACEABLE: #{problem}#{freed}"
                end

                return "Quad offset #{text} — release or click to place  (*4 array, /7 divide, BKSP back)"
            end

            ring  = @na_qo_hover
            edges = ring[:edges].length
            shape = ring[:closed] ? "#{edges}-edge ring" : "#{edges}-edge line"
            ahead = ring[:reach_pos] ? "#{Na__InsertPrimatives.Na__QuadRings__MmText(ring[:reach_pos])} mm" : 'open'
            back  = ring[:reach_neg] ? "#{Na__InsertPrimatives.Na__QuadRings__MmText(ring[:reach_neg])} mm" : 'open'

            "Quad line, #{shape}, run #{back} / #{ahead} either side — click and drag along the run to offset a new quad#{na_revise__status_hint}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where the Grabbed or Offered Ring Lives
        # ------------------------------------------------------------
        def na_qo__plane_description
            ring = @na_qo_target || @na_qo_hover
            "Quad line in #{Na__InsertPrimatives.Na__DeepPick__PathLabel(ring)}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Placed or Re-Made Quad Offset
        # ------------------------------------------------------------
        def na_qo__log(target, layout, offsets, stats, entered)
            source =
                if target[:kind] == :face
                    'the face loop (a loop cut, as an array)'
                else
                    "a #{target[:edges].length}-edge #{target[:closed] ? 'ring' : 'line'}"
                end

            ahead = target[:reach_pos] ? "#{Na__InsertPrimatives.Na__QuadRings__MmText(target[:reach_pos])}mm" : 'unmeasured'
            back  = target[:reach_neg] ? "#{Na__InsertPrimatives.Na__QuadRings__MmText(target[:reach_neg])}mm" : 'unmeasured'

            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts(
                na_revise__replaying? ? 'DEEP PUSH/PULL QUAD OFFSET ADJUSTED (retyped)' : 'DEEP PUSH/PULL QUAD OFFSET APPLIED'
            )
            Na__InsertPrimatives.Na__Debug__Puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "From   : #{source}"
            Na__InsertPrimatives.Na__Debug__Puts "Layout : #{na_qo__layout_text(layout)}"
            Na__InsertPrimatives.Na__Debug__Puts "Rings  : #{offsets.map { |offset| Na__InsertPrimatives.Na__QuadRings__MmText(offset) }.join(', ')} mm from the reference"
            Na__InsertPrimatives.Na__Debug__Puts "Run    : #{ahead} forward, #{back} back"
            Na__InsertPrimatives.Na__Debug__Puts "Edges  : #{stats[:kept]} kept, #{stats[:swept]} swept, #{stats[:faces_removed]} fill face(s) removed" \
                                                 "#{stats[:misplaced] ? ' — A RING LANDED IN THE WRONG SPACE and was removed' : ''}"
            Na__InsertPrimatives.Na__Debug__Puts "Context: #{entered ? 'entered for the cut, then restored' : 'already open'}"
            Na__InsertPrimatives.Na__Debug__Puts "Instances affected: #{target[:shared_count]}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA QUAD OFFSET: placed, and the report itself failed (#{error.message})"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say Out Loud Why a Quad Offset Was Not Made
        # ------------------------------------------------------------
        def na_qo__report_failure(target, layout, stats, reason)
            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts 'DEEP PUSH/PULL QUAD OFFSET REFUSED'
            Na__InsertPrimatives.Na__Debug__Puts "Reason : #{reason}"
            Na__InsertPrimatives.Na__Debug__Puts "Target : #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            Na__InsertPrimatives.Na__Debug__Puts "Layout : #{na_qo__layout_text(layout)}"
            if stats
                Na__InsertPrimatives.Na__Debug__Puts "Edges  : #{stats[:kept]} kept, #{stats[:swept]} swept#{stats[:misplaced] ? ', ring landed in the wrong space' : ''}"
            end
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        rescue StandardError => error
            Na__InsertPrimatives.Na__Debug__Puts "NA QUAD OFFSET: refused, and the report itself failed (#{error.message})"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullQuadOffset module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL QUAD OFFSET
# =============================================================================
