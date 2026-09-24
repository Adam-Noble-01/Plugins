# =============================================================================
# NA INSERT PRIMATIVES - DRAWN STAIRCASE TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnStairTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnStairTool < DrawnVolumeTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Draw a block, pick the side the flight rises from, drag the flight
#              inward, and carve an even set of steps out of the block
# CREATED    : 2026
#
# DESCRIPTION:
# - The first two gestures ARE the Drawn Volume tool, inherited whole: drag the
#   base rectangle, then the extrusion. Where the volume would place its box,
#   this tool asks two more questions instead.
# - SIDE: the block stays on screen and the side under the cursor lights up
#   blue, with an arrow pointing into the block. From above, where no side
#   faces the camera, it is the side whose top edge is nearest the cursor.
#   Click to rise from it.
# - FLIGHT: drag inward. The drag sets the RUN, the horizontal distance from
#   that side to the top riser; the rest of the block stays full height as the
#   landing. UP and DOWN add and remove a step. The pitch is written on the
#   steps the whole time, with a Part K check under it. Click or Enter builds.
#
# THE EVEN SET OF STEPS:
# - By default the steps interpolate evenly between the bottom and the top of
#   the block: rise = height / risers, going = run / (risers - 1). The first
#   riser stands on the chosen side and the landing is the last tread, which is
#   how a UK stair is counted. Geometry in DrawnStair__Geometry__.
# - A typed rise or going is EXACT instead. What each entry means, and when
#   one is refused, is in DrawnStair__Entry__.
#
# MEASUREMENTS BOX:
#   base stage    2400 | 2400,1200 | 2400,1200,2600   (the block, as Drawn Volume)
#   depth stage   2600 | +50 | -25
#   flight stage  35 (pitch) | 175r | 250g | 175r,250g | 9s | +1s   — builds it
#   after         the same entries correct the stair just built
#
# INHERITED, AND NOT:
# - Every base and depth behaviour is the volume's own: grid snapping, CTRL and
#   CTRL+SHIFT, TAB planes, arrow-key axis locks, typed pins and BKSP. In the
#   side and flight stages the arrows mean steps instead, and TAB does nothing.
# - The volume's popup options (Subtraction, Transparent) are answered false
#   here. They are read by option id rather than by mode key, so without that
#   a Subtraction left on in Drawn Volume would send this tool hunting for a
#   group to cut.
# - The flight drag takes Deep Chamfer's lesson: the cursor ray is cut with a
#   PLANE, not projected onto a line, so grabbing near either end of a wide
#   stair measures the same run as grabbing its middle.
#
# COORDINATES:
# - The whole tool works in world space, the same as Drawn Volume: the block,
#   the pick rays, the preview and the points the builder adds into a group
#   pinned to the world identity. No edit_transform anywhere.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../20__System__DrawnPrimitives/Na__InsertPrimatives__DrawnVolumeTool__'
require_relative 'Na__InsertPrimatives__DrawnStair__Geometry__'
require_relative 'Na__InsertPrimatives__DrawnStair__Entry__'
require_relative 'Na__InsertPrimatives__DrawnStair__Preview__'

module Na__InsertPrimatives

    # @delegate: Na__InsertPrimatives__DrawnStair__Geometry__.rb
    # @delegate: Na__InsertPrimatives__DrawnStair__Entry__.rb
    # @delegate: Na__InsertPrimatives__DrawnStair__Preview__.rb

    # -----------------------------------------------------------------------------
    # REGION | Drawn Staircase Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Draw a Block, Then Carve a Flight of Even Steps Out of It
    # ------------------------------------------------------------
    class DrawnStairTool < DrawnVolumeTool

        NA_STAIR_STAGES = [:picking_side, :picking_going].freeze

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            super
            na_stair__clear_live
            @na_stair_note = nil                                              # <-- Said once after a build, e.g. an exact rise moving the top
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Staircase'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_stair
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Drag out the block as Drawn Volume does: the base rectangle, then its height',
                'Click the side the stair rises from, then drag inward to set the flight',
                'UP / DOWN add and remove a step while the flight is live',
                'Every pick snaps to the voxel grid — hold CTRL to snap to vertices instead',
                'Hold CTRL+SHIFT to snap to a vertex and then round it onto the grid',
                'VCB block : 2400 pins W | 2400,1200 moves on | 2400,1200,2600 goes straight to the side',
                'VCB flight: 35 pitch | 175r rise | 250g going | 175r,250g | 9s risers | +1s',
                'A typed rise or going is exact — a typed rise moves the top to risers x rise',
                'Type straight after building to correct the stair in place'
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Drawn Volume's Subtraction Option Does Not Apply Here
        # ------------------------------------------------------------
        def na_volume__subtract_option?
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nor Does Its Transparent Option
        # ------------------------------------------------------------
        def na_volume__transparent_option?
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Stair Stage State
        # -----------------------------------------------------------------------------

        # FUNCTION | Is the Tool Past the Block, in a Stage of Its Own?
        # ------------------------------------------------------------
        def na_stair__stage?
            NA_STAIR_STAGES.include?(@na_state)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Block, the Side and the Flight Being Set Up
        # ------------------------------------------------------------
        def na_stair__clear_live
            @na_stair_box   = nil                                             # <-- The settled block, read back as an axis-aligned box
            @na_stair_side  = nil                                             # <-- :y_min / :x_max / :y_max / :x_min
            @na_stair_steps = NA_DRAWN_STAIR_MIN_STEPS
            @na_stair_run   = 0.0                                             # <-- The inward drag, internal inches
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Cancelled Drag Drops the Stair Set-Up With It
        # ------------------------------------------------------------
        def na_drawn__on_pick_state_reset
            super
            na_stair__clear_live
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Frame of the Side Currently Chosen or Hovered
        # ------------------------------------------------------------
        def na_stair__frame
            return nil unless @na_stair_box

            Na__InsertPrimatives.Na__DrawnStair__SideFrame(@na_stair_box, @na_stair_side)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Live Flight as a Stair State
        # Nothing is exact before the first build: the steps interpolate the
        # block, and the run is wherever the drag has it.
        # ------------------------------------------------------------
        def na_stair__live_state
            {
                :steps        => @na_stair_steps,
                :run          => @na_stair_run,
                :rise_strict  => nil,
                :going_strict => nil
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Number the Live Flight Is Made Of
        # ------------------------------------------------------------
        def na_stair__live_solve
            frame = na_stair__frame
            return nil unless frame

            Na__InsertPrimatives.Na__DrawnStair__Derive(frame, na_stair__live_state)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Number the Stair Just Built Is Made Of
        # ------------------------------------------------------------
        def na_stair__record_solve
            record = @na_last_record
            return nil unless record && record[:box] && record[:state]

            frame = Na__InsertPrimatives.Na__DrawnStair__SideFrame(record[:box], record[:side])
            Na__InsertPrimatives.Na__DrawnStair__Derive(frame, record[:state])
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Block Settled — Move On to Choosing the Side
        # ------------------------------------------------------------
        # Where Drawn Volume would build its box. The step count opens at the
        # whole number of risers nearest the target rise, so a fresh block
        # already shows a sensible flight the moment the drag starts.
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            unless na_drawn__rectangle_valid?
                UI.beep
                Sketchup::set_status_text('Base rectangle has no area', SB_PROMPT)
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                Sketchup::set_status_text('The block has no depth yet — drag further before clicking', SB_PROMPT)
                return false
            end

            box = Na__InsertPrimatives.Na__DrawnStair__BoxFrame(
                @na_point_a, @na_plane_key, na_drawn__signed_u, na_drawn__signed_v, na_drawn__signed_d
            )

            unless Na__InsertPrimatives.Na__DrawnStair__BoxUsable?(box)
                UI.beep
                Sketchup::set_status_text('That block cannot hold a stair — it needs width, depth and height', SB_PROMPT)
                return false
            end

            @na_stair_box   = box
            @na_stair_steps = Na__InsertPrimatives.Na__DrawnStair__DefaultSteps(box[:size][2])
            @na_stair_run   = 0.0
            @na_stair_side  = Na__InsertPrimatives.Na__DrawnStair__PickSide(
                view, box, @na_last_mouse_x, @na_last_mouse_y
            ) || :y_min
            @na_state       = :picking_side
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Side Chosen — Move On to the Flight
        # ------------------------------------------------------------
        # The press position is kept so that the second half of a double
        # click on the side is not mistaken for a click to build.
        # ------------------------------------------------------------
        def na_stair__advance_from_side(view, x, y)
            na_stair__hover_side(view, x, y)

            unless na_stair__frame
                UI.beep
                Sketchup::set_status_text('Hover a side of the block, then click it', SB_PROMPT)
                return false
            end

            @na_state     = :picking_going
            @na_stair_run = 0.0
            @na_press_x   = x
            @na_press_y   = y

            na_stair__update_run(view, x, y)
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Mouse, Enter and Double Click
        # -----------------------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Choose the Side, or Build the Stair
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_stair_note = nil if @na_state == :idle                        # <-- A new block: the last build's note has been read
            return super unless na_stair__stage?

            @na_vcb_typing_active = false
            @na_drag_press_active = false
            na_drawn__sync_modifier(flags)

            if @na_state == :picking_side
                na_stair__advance_from_side(view, x, y)
            else
                na_drawn__update_cursor(view, x, y)
                na_stair__commit(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOUBLE CLICK | Build, Unless It Is the Side Click's Echo
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            return super unless na_stair__stage?

            na_drawn__sync_modifier(flags)

            if @na_state == :picking_side
                na_stair__advance_from_side(view, x, y)
            else
                travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs
                return true if travelled_px < NA_DRAWN_DRAG_MIN_PX            # <-- The click that chose the side, arriving twice

                na_drawn__update_cursor(view, x, y)
                na_stair__commit(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # ON RETURN | Enter Chooses the Hovered Side, Then Builds
        # ------------------------------------------------------------
        def onReturn(view)
            return super unless na_stair__stage?

            if @na_state == :picking_side
                na_stair__advance_from_side(view, @na_last_mouse_x, @na_last_mouse_y)
            else
                na_stair__commit(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Keys — UP and DOWN Are the Step Count
        # -----------------------------------------------------------------------------

        # ON KEY DOWN | Arrows Change the Step Count Once the Block Is Settled
        # ------------------------------------------------------------
        # Through the base and depth stages every arrow keeps its axis-lock
        # meaning. Past them the block is fixed and there is no axis left to
        # lock, so UP and DOWN take over the step count and LEFT and RIGHT
        # say so rather than quietly locking an axis nothing reads.
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            if na_stair__stage? && (key == VK_UP || key == VK_DOWN)
                na_stair__nudge_steps(key == VK_UP ? 1 : -1, view)
                return false
            end

            if na_stair__stage? && (key == VK_LEFT || key == VK_RIGHT)
                Sketchup::set_status_text('LEFT / RIGHT lock nothing here — UP and DOWN add and remove a step', SB_PROMPT)
                return false
            end

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Add or Remove a Step, Holding the Run
        # ------------------------------------------------------------
        # The run stays where the drag put it, so a step more makes every
        # tread shorter and every riser lower: the flight fits the same span
        # with finer steps. At either limit the count holds and says why.
        # ------------------------------------------------------------
        def na_stair__nudge_steps(delta, view)
            height  = @na_stair_box ? @na_stair_box[:size][2] : 0.0
            wanted  = @na_stair_steps.to_i + delta
            clamped = Na__InsertPrimatives.Na__DrawnStair__ClampSteps(wanted, height)

            if clamped != wanted
                UI.beep
                message =
                    if delta < 0
                        "A stair needs at least #{NA_DRAWN_STAIR_MIN_STEPS} risers"
                    else
                        "#{clamped} risers is the most this block takes — another would rise under " \
                        "#{Na__InsertPrimatives.Na__DrawnStair__FormatMm(NA_DRAWN_STAIR_MIN_RISE)}"
                    end
                Sketchup::set_status_text(message, SB_PROMPT)
            end

            @na_stair_steps = clamped

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Has No Plane to Cycle Once the Block Is Settled
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            return super unless na_stair__stage?

            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP Steps Back One Stage: Flight, Side, Then the Block
        # ------------------------------------------------------------
        # The shared step-back peels typed pins first, but those pins belong
        # to the block's stages; past them BKSP just goes back a stage.
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            return super unless na_stair__stage?

            if @na_state == :picking_going
                @na_state     = :picking_side
                @na_stair_run = 0.0
            else
                @na_state     = :picking_depth
                @na_stair_box = nil
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cursor Tracking
        # -----------------------------------------------------------------------------

        # FUNCTION | Hover a Side, or Measure the Inward Drag
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            return super unless na_stair__stage?

            @na_last_mouse_x = x
            @na_last_mouse_y = y

            if @na_state == :picking_side
                na_stair__hover_side(view, x, y)
            else
                na_stair__update_run(view, x, y)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Follow the Side Under the Cursor
        # A frame nothing could be projected in keeps the side it had.
        # ------------------------------------------------------------
        def na_stair__hover_side(view, x, y)
            side = Na__InsertPrimatives.Na__DrawnStair__PickSide(view, @na_stair_box, x, y)
            @na_stair_side = side if side
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measure the Run from the Chosen Side
        # ------------------------------------------------------------
        # The travel is the hit's component along the inward direction,
        # measured from the side's top edge, then rounded onto the grid the
        # way Deep Chamfer rounds its setback: the side stands on the
        # lattice, so a rounded run puts the landing edge on it too. CTRL
        # takes the InputPoint instead, so the landing edge can be run up to
        # a vertex (the edge of an upper floor, say), and CTRL+SHIFT rounds
        # that as well. The run is held inside the block.
        #
        # The snapped cursor point is the source slid along the inward
        # direction by whatever the rounding and the limits took off, which is
        # where the CTRL+SHIFT mark then draws its square.
        # ------------------------------------------------------------
        def na_stair__update_run(view, x, y)
            frame = na_stair__frame
            return false unless frame

            source =
                if @na_ctrl_held
                    na_drawn__input_point_position(view, x, y)
                else
                    Na__InsertPrimatives.Na__DrawnStair__RunPlanePoint(view, x, y, frame)
                end
            return false unless source                                        # <-- Edge-on to both planes: keep the last good run

            travel = (source - frame[:top_start]).dot(frame[:inward]).to_f
            run    = na_drawn__snap_distance(travel).to_f
            run    = 0.0            if run < 0.0
            run    = frame[:depth]  if run > frame[:depth]

            @na_stair_run      = run
            @na_cursor_raw     = source
            @na_cursor_snapped = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(source, frame[:inward], run - travel)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The InputPoint Marker Means Nothing While a Side Is Hovered
        # ------------------------------------------------------------
        def na_drawn__inference_visible?
            return false if @na_state == :picking_side

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nor Does the CTRL+SHIFT Correction Mark
        # ------------------------------------------------------------
        def na_drawn__draw_grid_correction(view)
            return if @na_state == :picking_side

            super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Side Being Chosen, or the Flight Being Dragged
        # The base and depth stages are the volume's own preview, untouched.
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            return super unless na_stair__stage?

            frame = na_stair__frame
            return unless frame

            if @na_state == :picking_side
                Na__InsertPrimatives.Na__DrawnStair__DrawSideStage(view, @na_stair_box, frame, @na_stair_steps)
                return
            end

            Na__InsertPrimatives.Na__DrawnStair__DrawFlightStage(view, @na_stair_box, frame, na_stair__live_solve)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Preview Occupies
        # The flight never leaves the block before it is built, so the block's
        # corners bound everything drawn.
        # ------------------------------------------------------------
        def na_drawn__preview_points
            return super unless na_stair__stage? && @na_stair_box

            Na__InsertPrimatives.Na__DrawnStair__BoxCorners(@na_stair_box)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            width_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_u).abs
            height_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_v).abs
            depth_mm  = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs

            case @na_state
            when :picking_b
                "W #{width_mm} x H #{height_mm} mm — release or click to set the base of the block"
            when :picking_depth
                "W #{width_mm} x H #{height_mm} x D #{depth_mm} mm — click to settle the block, then pick the side the stair rises from"
            when :picking_side
                na_stair__side_status
            when :picking_going
                na_stair__flight_status
            else
                return "#{@na_stair_note}Type 35, 175r, 250g or 9s to correct the stair just built" if na_drawn__revise_available?

                'Click and drag out the stair block — base, then height'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status While a Side Is Being Chosen
        # ------------------------------------------------------------
        def na_stair__side_status
            frame = na_stair__frame
            return 'Hover the side the stair rises from' unless frame

            "Rise from the #{NA_DRAWN_STAIR_SIDE_LABELS[frame[:side]]} side, " \
            "#{Na__InsertPrimatives.Na__DrawnStair__FormatMm(frame[:width])} wide — click to choose it"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status While the Flight Is Being Dragged
        # ------------------------------------------------------------
        def na_stair__flight_status
            solve = na_stair__live_solve

            unless solve && solve[:run] > NA_DRAWN_STAIR_MERGE_TOL.to_f
                return "Drag inward to set the flight — #{@na_stair_steps} risers, UP / DOWN to change"
            end

            "#{solve[:steps]} risers of #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:rise])}, " \
            "goings of #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:going])}, " \
            "pitch #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:pitch])}° — " \
            'click to build, or type 35 · 175r · 250g'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Short Status Fragment: the Step Count, Then the Part K Check
        # ------------------------------------------------------------
        def na_stair__check_fragment
            return "#{@na_stair_steps} risers" unless @na_state == :picking_going

            solve = na_stair__live_solve
            return "#{@na_stair_steps} risers" unless solve && solve[:run] > NA_DRAWN_STAIR_MERGE_TOL.to_f

            Na__InsertPrimatives.Na__DrawnStair__PartKText(Na__InsertPrimatives.Na__DrawnStair__PartK(solve), true)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push the Composed Status Line
        # ------------------------------------------------------------
        # The shared line advertises TAB planes and arrow axis locks, which
        # stop being true once the block is settled, so the stair stages
        # compose their own. Sent only when it changes, like the shared one.
        # ------------------------------------------------------------
        def na_drawn__update_status_text
            return super unless na_stair__stage?

            composed =
                "#{na_drawn__tool_title} | #{na_drawn__status_detail} | " \
                "#{na_drawn__grid_description} | #{na_stair__check_fragment} | " \
                "UP/DOWN steps  #{na_drawn__vertex_hint}  BKSP back  ESC cancel"

            return if composed == @na_last_status_text

            Sketchup::set_status_text(composed, SB_PROMPT)
            @na_last_status_text = composed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        # From the flight stage on, the box shows the PITCH, because a bare
        # number typed into it is a pitch. A rise or going shown there would
        # invite exactly the entry that needs its letter.
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            case @na_state
            when :picking_b
                ['Block W,H,D', na_drawn__format_sizes([@na_size_u, @na_size_v, @na_size_d])]
            when :picking_depth
                ['Block depth', na_drawn__format_sizes([@na_size_d])]
            when :picking_side
                ['Stair side', '']
            when :picking_going
                ['Stair pitch', na_stair__pitch_text(na_stair__live_solve)]
            else
                return ['Block W,H,D', ''] unless na_drawn__revise_available?

                ['Stair pitch', na_stair__pitch_text(na_stair__record_solve)]
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Solve's Pitch as the Measurements Box Shows It
        # ------------------------------------------------------------
        def na_stair__pitch_text(solve)
            return '' unless solve && solve[:run] > NA_DRAWN_STAIR_MERGE_TOL.to_f

            "#{Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:pitch])}°"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | Route a Typed Entry by Stage
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            case @na_state
            when :picking_b, :picking_depth
                na_stair__handle_block_text(text, view)

            when :picking_side
                UI.beep
                Sketchup::set_status_text('Click the side the stair rises from first — the pitch, rise or going comes after', SB_PROMPT)
                false

            when :picking_going
                request = Na__InsertPrimatives.Na__DrawnStair__ParseEntry(text)
                state   = Na__InsertPrimatives.Na__DrawnStair__ResolveEntry(na_stair__frame, na_stair__live_state, request)
                na_stair__commit(view, state)

            when :idle
                unless na_drawn__revise_available?
                    UI.beep
                    Sketchup::set_status_text('Click a start corner before typing a size', SB_PROMPT)
                    return false
                end

                na_stair__revise(view, Na__InsertPrimatives.Na__DrawnStair__ParseEntry(text))

            else
                UI.beep
                false
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Block Size, Exactly as Drawn Volume Reads One
        # ------------------------------------------------------------
        # The one difference: where the volume would place its box once all of
        # W,H,D are known, this moves on to the side stage.
        # ------------------------------------------------------------
        def na_stair__handle_block_text(text, view)
            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)

            if @na_state == :picking_depth
                raise ArgumentError, 'depth takes a single value' if tokens.length > 1

                depths = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(tokens, [@na_size_d])
                Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(depths, ['Depth'])
                @na_size_d = depths[0]
                na_drawn__lock_slot(:d)
                return na_drawn__advance_from_depth(view)
            end

            raise ArgumentError, 'the block takes one value, W,H or W,H,D' if tokens.length > 3

            if tokens.length == 3
                @na_sign_d = 1.0                                              # <-- Nothing has dragged a depth yet: a typed one grows up the normal
                na_drawn__apply_typed_sizes(tokens, 3)

                return na_drawn__advance_from_depth(view) if na_drawn__all_locked?([:u, :v, :d])
                return true unless na_drawn__all_locked?([:u, :v])
                return na_drawn__advance_from_b(view)
            end

            na_drawn__apply_typed_sizes(tokens, 2)
            return true unless na_drawn__all_locked?([:u, :v])                 # <-- One side named: pin it, keep dragging the other

            na_drawn__advance_from_b(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit and Revise
        # -----------------------------------------------------------------------------

        # FUNCTION | Build the Stair
        # ------------------------------------------------------------
        # `state` is the live flight unless a typed entry resolved one. The
        # record keeps the block, the side and the state rather than the
        # numbers, so a retype re-solves from the same decisions and an exact
        # rise or going stays exact.
        # ------------------------------------------------------------
        def na_stair__commit(view, state = nil)
            frame = na_stair__frame

            unless frame
                UI.beep
                Sketchup::set_status_text('Pick the side the stair rises from first', SB_PROMPT)
                return false
            end

            state ||= na_stair__live_state
            solve   = Na__InsertPrimatives.Na__DrawnStair__Derive(frame, state)
            refusal = Na__InsertPrimatives.Na__DrawnStair__BuildRefusal(solve)

            if refusal
                UI.beep
                Sketchup::set_status_text(refusal, SB_PROMPT)
                return false
            end

            group = Na__InsertPrimatives.Na__DrawnStair__CreateStair(frame, solve)

            unless group
                UI.beep
                Sketchup::set_status_text('Could not build a staircase here', SB_PROMPT)
                return false
            end

            @na_last_record = {
                :group   => group,
                :box     => @na_stair_box,
                :side    => @na_stair_side,
                :state   => state,
                :context => na_stair__context_ids
            }

            Na__InsertPrimatives.Na__DrawnStair__RememberRise(solve[:rise])
            na_drawn__reset_pick_state
            na_drawn__arm_revise
            @na_stair_note = Na__InsertPrimatives.Na__DrawnStair__HeightNote(frame, solve)
            na_stair__log('STAIRCASE CREATED', group, frame, solve)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Last Stair from a Typed Correction
        # ------------------------------------------------------------
        # The rebuild sets the group back to the world identity and adds world
        # points, which is only right in the context the stair was built in.
        # Closing or opening a group in between would move where "identity"
        # is, so a correction there is refused instead of landing somewhere else.
        # ------------------------------------------------------------
        def na_stair__revise(view, request)
            record = @na_last_record
            return false unless record

            unless na_stair__context_ids == record[:context]
                UI.beep
                Sketchup::set_status_text('That stair was built in another editing context — open it again, or draw a new one', SB_PROMPT)
                return false
            end

            frame   = Na__InsertPrimatives.Na__DrawnStair__SideFrame(record[:box], record[:side])
            state   = Na__InsertPrimatives.Na__DrawnStair__ResolveEntry(frame, record[:state], request)
            solve   = Na__InsertPrimatives.Na__DrawnStair__Derive(frame, state)
            refusal = Na__InsertPrimatives.Na__DrawnStair__BuildRefusal(solve)

            if refusal
                UI.beep
                Sketchup::set_status_text(refusal, SB_PROMPT)
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnStair__RebuildStair(record[:group], frame, solve)
                UI.beep
                Sketchup::set_status_text('Could not rebuild that staircase', SB_PROMPT)
                return false
            end

            record[:state] = state
            Na__InsertPrimatives.Na__DrawnStair__RememberRise(solve[:rise])
            na_drawn__arm_revise                                               # <-- Keep correcting while the mouse stays put
            @na_stair_note = Na__InsertPrimatives.Na__DrawnStair__HeightNote(frame, solve)
            na_stair__log('STAIRCASE ADJUSTED', record[:group], frame, solve)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Open Editing Context, as Entity Ids
        # ------------------------------------------------------------
        def na_stair__context_ids
            model = Sketchup.active_model
            path  = model ? model.active_path : nil

            (path || []).map { |entity| entity.valid? ? entity.entityID : nil }
        rescue StandardError
            []
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Built or Adjusted Stair
        # ------------------------------------------------------------
        def na_stair__log(headline, group, frame, solve)
            partk   = Na__InsertPrimatives.Na__DrawnStair__PartK(solve)
            landing = solve[:landing] > NA_DRAWN_STAIR_MERGE_TOL.to_f ? Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:landing]) : 'none'

            Na__InsertPrimatives.Na__Debug__Puts "\n"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
            Na__InsertPrimatives.Na__Debug__Puts headline
            Na__InsertPrimatives.Na__Debug__Puts "Block : #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(frame[:width])} wide x " \
                                                 "#{Na__InsertPrimatives.Na__DrawnStair__FormatMm(frame[:depth])} deep x " \
                                                 "#{Na__InsertPrimatives.Na__DrawnStair__FormatMm(frame[:height])} high, " \
                                                 "rising from the #{NA_DRAWN_STAIR_SIDE_LABELS[frame[:side]]} side"
            Na__InsertPrimatives.Na__Debug__Puts "Flight: #{solve[:steps]} risers of #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:rise])} · " \
                                                 "#{solve[:steps] - 1} goings of #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:going])}"
            Na__InsertPrimatives.Na__Debug__Puts "Run   : #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:run])} · landing #{landing} · " \
                                                 "total rise #{Na__InsertPrimatives.Na__DrawnStair__FormatMm(solve[:height])}"
            Na__InsertPrimatives.Na__Debug__Puts "Pitch : #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(solve[:pitch])}°"
            Na__InsertPrimatives.Na__Debug__Puts "Check : #{Na__InsertPrimatives.Na__DrawnStair__PartKText(partk)}"
            Na__InsertPrimatives.Na__Debug__Puts "Solid : #{Na__InsertPrimatives.Na__DrawnGeom__SolidState(group)}"
            Na__InsertPrimatives.Na__Debug__Puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            Na__InsertPrimatives.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnStairTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Activate the Drawn Staircase Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    # Bind in Preferences -> Shortcuts against the Plugins menu item, or call
    # directly: Na__InsertPrimatives.Na__InsertPrimatives__DrawStair
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DrawStair
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnStairTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN STAIRCASE TOOL MODULE
# =============================================================================
