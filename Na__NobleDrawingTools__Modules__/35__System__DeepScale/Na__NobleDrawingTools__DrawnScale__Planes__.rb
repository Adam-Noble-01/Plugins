# =============================================================================
# NA NOBLE DRAWING TOOLS - DEEP SCALE STRETCH PLANES (TOOL HALF)
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnScale__Planes__.rb
# NAMESPACE  : Na__NobleDrawingTools::DrawnScalePlanes
# AUTHOR     : Noble Architecture
# PURPOSE    : Place, drag, mirror and remove stretch planes on the object
#              Deep Scale is holding, and draw them
# CREATED    : 2026
#
# DESCRIPTION:
# - With Stretch Planes on, an axis with no plane of its own has a CENTRE PLANE,
#   worked out and never stored (5.2.22, Field file). This file is how to put
#   one somewhere else. It looks and drags like any other plane, with a diamond
#   of its own beside the other two where the three cross, and it only reaches
#   the object if it is moved. DEL cannot remove it, only SHIFT+TAB can.
# - TWO WAYS TO ADD A PLANE, and every one ADDS (5.2.6; until then a click
#   without CTRL replaced the axis's planes, which read as "only one plane"),
#   except that the first on an axis takes over from its centre plane:
#     click a centre line   with Stretch Planes on, each axis shows a
#                           dashed centre line in its colour; press on it
#                           to drop a plane there and drag it into place
#     hold CTRL             anywhere over the object, Planes on or off: a
#                           plane follows the cursor along the nearest
#                           centre line's axis (an ARROW picks the axis);
#                           click to add it. Planes switch on with it.
#   It snaps to points, and to edges and faces that run square across the
#   axis, and otherwise to the grid. Release and it is saved on the object.
#   SHIFT drops a mirrored pair about the middle, for the symmetrical frames
#   most doors and windows are. Add as many as the object has panels.
# - Press on a plane's diamond to drag it (SHIFT moves its mirror with it). Let
#   go and it stays selected, drawn as if the cursor were on it, until ESC or a
#   click elsewhere (5.2.27). DEL removes the plane under the cursor, or else the
#   selected one, as does a double-click on the diamond, and the last one to go
#   leaves the centre plane back in its place. DEL never reaches the object: see
#   the Keys file. Right after placing or moving one, a typed value sets its
#   distance from the low end. Clear Stretch Planes (right-click menu) removes
#   all that were placed.
# - Loose geometry and a selection of several objects have nowhere to save a
#   plane. Until 5.2.41 they kept their centre planes only; now their planes
#   are placed, moved and removed like an object's, and the TOOL keeps them
#   (@na_sc_loose_planes) for as long as it holds that selection: carried
#   through each stretch or scale, brought back by Ctrl+Z with the shape they
#   went with, and forgotten when another selection is taken. No undo step.
# - A line of help under the mode strip says which of these applies right
#   now, so none of it has to be remembered.
# - The planes in this file are only ever a WORKING COPY until the mouse is
#   released: ESC mid-drag puts back exactly what was there, and each
#   placement is one undo step.
#
# HOST CONTRACT (DrawnScaleTool):
#   @na_sc_frame, @na_sc_planes  the frame and its saved planes
#   na_scale__planes_on?         Stretch Planes switched on
#   na_scale__say                a result for the status line
#   @na_ip, @na_ctrl_held, @na_shift_held from DrawnToolShared
#
# =============================================================================

require 'sketchup.rb'

module Na__NobleDrawingTools

    # =============================================================================
    # MODULE | Deep Scale Stretch Planes
    # =============================================================================

    module DrawnScalePlanes

        NA_SCALE_HANDLE_HIT_PX = 9.0
        NA_SCALE_LINE_HIT_PX   = 9.0
        NA_SCALE_HANDLE_SPREAD_PX = 18.0                                      # <-- Diamonds of different axes closer than this are moved apart: twice the hit radius
        NA_SCALE_CTRL_REACH_PX = 40.0                                         # <-- CTRL offers a plane this far outside the object's outline on screen

        # -----------------------------------------------------------------------------
        # REGION | Finding Planes Under the Cursor
        # -----------------------------------------------------------------------------

        # FUNCTION | The Planes to Show — the Working Copy Mid-Drag, Else the Saved Ones
        # ------------------------------------------------------------
        def na_scale__shown_planes
            return @na_sc_plane_drag[:planes] if @na_sc_plane_drag

            @na_sc_planes || Na__NobleDrawingTools.Na__ScalePlanes__Empty
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Plane's Diamond, With Where It Sits on Screen
        # ------------------------------------------------------------
        def na_scale__plane_handles(view)
            frame = @na_sc_frame
            return [] unless frame

            handles = []
            planes  = na_scale__shown_planes

            NA_SCALE_AXES.each_with_index do |axis, n|
                next unless frame[:usable][n]

                (planes[axis] || []).each_with_index do |value, index|
                    world  = Na__NobleDrawingTools.Na__ScalePlanes__HandlePoint(frame, axis, value)
                    screen = Na__NobleDrawingTools.Na__ScalePreview__Screen(view, world)
                    next unless screen

                    handles << { :axis => axis, :index => index, :u => value, :world => world, :screen => screen }
                end
            end

            na_scale__spread_handles(view, handles)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Move Diamonds Standing on Each Other Apart, Along Their Own Lines
        # ------------------------------------------------------------
        # Three centre planes cross at one point, and three diamonds on one
        # spot would leave only one of them to be grabbed. Each is moved along
        # its own axis's centre line on screen, one by one until none is
        # crowded. Only the diamond moves, not the plane. An axis seen end-on
        # has no line to move along, so it keeps the spot.
        # ------------------------------------------------------------
        def na_scale__spread_handles(view, handles)
            handles.each do |handle|
                crowded = handles.any? do |other|
                    other[:axis] != handle[:axis] &&
                        Math.hypot(other[:screen].x - handle[:screen].x, other[:screen].y - handle[:screen].y) < NA_SCALE_HANDLE_SPREAD_PX
                end
                next unless crowded

                ends = Na__NobleDrawingTools.Na__DrawnPreview__ScreenPoints(view, Na__NobleDrawingTools.Na__ScalePlanes__CentreLine(@na_sc_frame, handle[:axis]))
                next unless ends && ends[0].distance(ends[1]) >= NA_SCALE_MIN_EDGE_PIXELS

                unit = Na__NobleDrawingTools.Na__ScalePreview__Unit(ends[1].x - ends[0].x, ends[1].y - ends[0].y)
                handle[:screen] = Geom::Point3d.new(handle[:screen].x + (unit[0] * NA_SCALE_HANDLE_SPREAD_PX), handle[:screen].y + (unit[1] * NA_SCALE_HANDLE_SPREAD_PX), 0)
            end

            handles
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Axis Stretching at Its Centre Plane, Having None of Its Own?
        # ------------------------------------------------------------
        def na_scale__centre_plane?(axis)
            return false unless na_scale__planes_on? && @na_sc_frame

            Na__NobleDrawingTools.Na__ScalePlanes__LoneCentre?(@na_sc_frame, axis, na_scale__shown_planes[axis])
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane Diamond Under the Cursor, or nil
        # ------------------------------------------------------------
        def na_scale__handle_at(view, x, y)
            best      = nil
            best_dist = nil

            na_scale__plane_handles(view).each do |handle|
                dx   = handle[:screen].x - x
                dy   = handle[:screen].y - y
                dist = Math.sqrt((dx * dx) + (dy * dy))
                next if dist > NA_SCALE_HANDLE_HIT_PX
                next if best_dist && dist >= best_dist

                best      = handle
                best_dist = dist
            end

            best
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Axis Whose Centre Line Is Under the Cursor, or nil
        # ------------------------------------------------------------
        def na_scale__line_at(view, x, y)
            frame = @na_sc_frame
            return nil unless frame

            best      = nil
            best_dist = nil

            NA_SCALE_AXES.each_with_index do |axis, n|
                next unless frame[:usable][n]

                ends   = Na__NobleDrawingTools.Na__ScalePlanes__CentreLine(frame, axis)
                screen = Na__NobleDrawingTools.Na__DrawnPreview__ScreenPoints(view, ends)
                next unless screen
                next if screen[0].distance(screen[1]) < NA_SCALE_MIN_EDGE_PIXELS      # <-- Seen end-on: a dot, not a line to drop a plane on

                dist = Na__NobleDrawingTools.Na__ScalePreview__SegmentDistance(x, y, screen[0], screen[1])
                next if dist > NA_SCALE_LINE_HIT_PX
                next if best_dist && dist >= best_dist

                best      = axis
                best_dist = dist
            end

            best
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Axis CTRL Offers a Plane On, or nil
        # ------------------------------------------------------------
        # Anywhere over the object, or just off its outline: the axis whose
        # centre line is nearest the cursor on screen, so the plane offered is
        # the one the hand is closest to. An arrow lock names it outright.
        # An axis seen end-on is never offered: its plane would face the eye.
        # ------------------------------------------------------------
        def na_scale__ctrl_axis(view, x, y)
            frame = @na_sc_frame
            return nil unless frame

            corners =Na__NobleDrawingTools.Na__ScaleFrame__BoxQuads(frame, frame[:min], frame[:max]).flatten
            screen  = Na__NobleDrawingTools.Na__DrawnPreview__ScreenPoints(view, corners)
            return nil unless screen && Na__NobleDrawingTools.Na__ScalePreview__Sane?(screen)

            reach = NA_SCALE_CTRL_REACH_PX
            return nil if x < screen.map(&:x).min - reach || x > screen.map(&:x).max + reach
            return nil if y < screen.map(&:y).min - reach || y > screen.map(&:y).max + reach

            best      = nil
            best_dist = nil

            NA_SCALE_AXES.each_with_index do |axis, n|
                next unless frame[:usable][n]
                next if @na_axis_lock && @na_axis_lock != axis

                ends = Na__NobleDrawingTools.Na__DrawnPreview__ScreenPoints(view, Na__NobleDrawingTools.Na__ScalePlanes__CentreLine(frame, axis))
                next unless ends && ends[0].distance(ends[1]) >= NA_SCALE_MIN_EDGE_PIXELS

                dist = Na__NobleDrawingTools.Na__ScalePreview__SegmentDistance(x, y, ends[0], ends[1])
                next if best_dist && dist >= best_dist

                best      = axis
                best_dist = dist
            end

            best
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is CTRL Offering a Plane Right Now?
        # ------------------------------------------------------------
        def na_scale__ctrl_offer?
            @na_sc_hover && @na_sc_hover[:kind] == :line && @na_sc_hover[:ctrl] ? true : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where a Plane Would Go for the Cursor: [u, how] or nil
        # ------------------------------------------------------------
        def na_scale__plane_snap(view, axis, x, y)
            @na_ip.pick(view, x, y)
            snapped = Na__NobleDrawingTools.Na__ScalePlanes__SnapValue(view, @na_sc_frame, axis, @na_ip, x, y)
            return nil unless snapped

            [Na__NobleDrawingTools.Na__ScalePlanes__Clamp(@na_sc_frame, axis, snapped[0]), snapped[1]]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Mirror of a Plane About the Middle of Its Axis
        # ------------------------------------------------------------
        def na_scale__mirror_value(axis, value)
            n = NA_SCALE_AXIS_INDEX[axis]
            @na_sc_frame[:min][n] + @na_sc_frame[:max][n] - value
        end
        # ---------------------------------------------------------------

        # FUNCTION | Are Two Plane Positions the Same Plane?
        # ------------------------------------------------------------
        def na_scale__same_plane?(axis, first, second)
            n     = NA_SCALE_AXIS_INDEX[axis]
            merge = (NA_SCALE_PLANE_MERGE_MM / NA_DRAWN_INCH_TO_MM) / @na_sc_frame[:scales][n]
            (first - second).abs < merge
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Placing and Dragging
        # -----------------------------------------------------------------------------

        # FUNCTION | Copy a Plane Set So the Drag Can Change It Freely
        # ------------------------------------------------------------
        def na_scale__copy_planes(planes)
            copy = Na__NobleDrawingTools.Na__ScalePlanes__Empty
            NA_SCALE_AXES.each { |axis| copy[axis] = (planes[axis] || []).map(&:to_f) }
            copy
        end
        # ---------------------------------------------------------------

        # FUNCTION | Press on a Centre Line, or With CTRL — Add a Plane and Hold It
        # ------------------------------------------------------------
        # Always added to the planes the axis already has. One click on a
        # fresh object is the first plane, taking over from the centre plane
        # that stood in for it; the next click is the second.
        # ------------------------------------------------------------
        def na_scale__begin_new_plane(view, axis, x, y)
            snapped = na_scale__plane_snap(view, axis, x, y)
            return false unless snapped

            value, how = snapped
            planes     = na_scale__copy_planes(@na_sc_planes || Na__NobleDrawingTools.Na__ScalePlanes__Empty)
            planes[axis] = [] if na_scale__centre_plane?(axis)
            list       = planes[axis]
            list << value
            index      = list.length - 1
            mirror     = nil

            if @na_shift_held
                twin = na_scale__mirror_value(axis, value)

                unless na_scale__same_plane?(axis, twin, value)
                    list << twin
                    mirror = list.length - 1
                end
            end

            planes[axis] = list
            na_scale__hold_plane(axis, index, mirror, planes, how, x, y, true)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Press on a Plane's Diamond — Pick It Up to Move It
        # SHIFT picks its mirror up with it, when it has one.
        # ------------------------------------------------------------
        def na_scale__begin_move_plane(view, handle, x, y)
            planes = na_scale__copy_planes(@na_sc_planes || Na__NobleDrawingTools.Na__ScalePlanes__Empty)
            axis   = handle[:axis]
            mirror = nil

            if @na_shift_held
                twin   = na_scale__mirror_value(axis, handle[:u])
                mirror = planes[axis].each_index.find do |index|
                    index != handle[:index] && na_scale__same_plane?(axis, planes[axis][index], twin)
                end
            end

            na_scale__hold_plane(axis, handle[:index], mirror, planes, nil, x, y, false)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Start Holding a Plane
        # ------------------------------------------------------------
        def na_scale__hold_plane(axis, index, mirror, planes, how, x, y, created)
            @na_sc_plane_drag = {
                :axis    => axis,
                :index   => index,
                :mirror  => mirror,
                :planes  => planes,
                :how     => how,
                :press_x => x,
                :press_y => y,
                :moved   => false,
                :created => created
            }

            @na_sc_plane_hover = nil
            @na_sc_focus       = :plane
            @na_sc_active_plane = { :axis => axis, :u => planes[axis][index] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Held Plane Follows the Cursor Along Its Axis
        # ------------------------------------------------------------
        def na_scale__update_plane_drag(view, x, y)
            drag = @na_sc_plane_drag
            return false unless drag

            travelled     = (x.to_f - drag[:press_x].to_f).abs + (y.to_f - drag[:press_y].to_f).abs
            drag[:moved]  = true if travelled >= Na__NobleDrawingTools::DrawnToolShared::NA_DRAWN_DRAG_MIN_PX
            return false unless drag[:moved]

            snapped = na_scale__plane_snap(view, drag[:axis], x, y)
            return false unless snapped

            value, how = snapped
            list       = drag[:planes][drag[:axis]]
            list[drag[:index]] = value
            drag[:how] = how

            if drag[:mirror]
                list[drag[:mirror]] = Na__NobleDrawingTools.Na__ScalePlanes__Clamp(
                    @na_sc_frame, drag[:axis], na_scale__mirror_value(drag[:axis], value)
                )
            end

            @na_sc_active_plane = { :axis => drag[:axis], :u => value }
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Release — Save the Planes as One Undo Step
        # ------------------------------------------------------------
        # A diamond pressed and let go without moving saves nothing: that is
        # the first half of a double-click, or a selection, not a change. What
        # was last said gives way, so the status line says it is selected.
        # ------------------------------------------------------------
        def na_scale__release_plane_drag(view)
            drag = @na_sc_plane_drag
            return false unless drag

            @na_sc_plane_drag = nil

            unless drag[:created] || drag[:moved]
                @na_sc_message = nil
                return true
            end

            value = drag[:planes][drag[:axis]][drag[:index]]
            na_scale__save_planes(drag[:planes], NA_SCALE_OP_PLANE)

            @na_sc_active_plane = { :axis => drag[:axis], :u => value }
            @na_sc_last_placed  = { :at => Time.now, :axis => drag[:axis], :u => value } if drag[:created]

            low, high = Na__NobleDrawingTools.Na__ScalePlanes__DistancesMm(@na_sc_frame, drag[:axis], value)
            pair      = drag[:mirror] ? ' (mirrored pair)' : ''
            na_scale__say(
                "#{drag[:axis].to_s.upcase} plane #{drag[:created] ? 'placed' : 'moved'} at #{low} | #{high} mm#{pair} — type a distance from the low end to set it exactly"
            )
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | ESC Mid-Drag — Put Back What Was There
        # ------------------------------------------------------------
        def na_scale__cancel_plane_drag
            return false unless @na_sc_plane_drag

            @na_sc_plane_drag   = nil
            @na_sc_active_plane = nil
            @na_sc_focus        = nil if @na_sc_focus == :plane
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Saving, Typing and Removing
        # -----------------------------------------------------------------------------

        # FUNCTION | Tidy a Plane Set and Save It on the Object
        # ------------------------------------------------------------
        # planes is what was on show, centre planes and all. Those are taken
        # out here, so moving one plane does not store the two beside it. With
        # nothing to store and nothing stored there is no undo step to make.
        # A held selection's go to the tool instead (5.2.41): no undo step.
        # ------------------------------------------------------------
        def na_scale__save_planes(planes, op_name)
            frame = @na_sc_frame
            return false unless frame

            tidy = Na__NobleDrawingTools.Na__ScalePlanes__Prune(planes, frame[:min], frame[:max])  # <-- Orphans go whenever the planes are written
            NA_SCALE_AXES.each_with_index do |axis, n|
                tidy[axis] = Na__NobleDrawingTools.Na__ScalePlanes__Tidy(tidy[axis], frame, n)
            end
            tidy = Na__NobleDrawingTools.Na__ScalePlanes__WithoutCentres(frame, tidy)

            if frame[:loose]
                na_scale__keep_loose_planes(tidy)
                @na_sc_planes = na_scale__planes_of(frame)
                return true
            end

            nothing =Na__NobleDrawingTools.Na__ScalePlanes__Total(tidy).zero? &&
                      Na__NobleDrawingTools.Na__ScalePlanes__Total(Na__NobleDrawingTools.Na__ScalePlanes__Read(frame[:definition])).zero?
            saved   = nothing || Na__NobleDrawingTools.Na__ScaleCommit__SavePlanes(Sketchup.active_model, frame[:definition], tidy, op_name)
            @na_sc_planes = na_scale__planes_of(frame) if saved
            saved
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Distance From the Low End Moves the Active Plane
        # ------------------------------------------------------------
        def na_scale__type_plane(text, view)
            active = @na_sc_active_plane
            frame  = @na_sc_frame
            raise ArgumentError, 'place or click a plane before typing its position' unless active && frame

            tokens = Na__NobleDrawingTools.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'a plane takes one distance, from the low end of the object' if tokens.length > 1

            axis    = active[:axis]
            n       = NA_SCALE_AXIS_INDEX[axis]
            scale   = frame[:scales][n]
            current = (active[:u] - frame[:min][n]) * scale
            along   = Na__NobleDrawingTools.Na__DrawnVcb__ApplyToken(tokens[0], current)

            unless along > 0.0 && along < frame[:world_lengths][n]
                raise ArgumentError, "a #{axis.to_s.upcase} plane has to sit inside the object — 0 to #{Na__NobleDrawingTools.Na__DrawnFormat__Mm(frame[:world_lengths][n])} mm from the low end"
            end

            value  = frame[:min][n] + (along / scale)
            source = @na_sc_plane_drag ? @na_sc_plane_drag[:planes] : (@na_sc_planes || Na__NobleDrawingTools.Na__ScalePlanes__Empty)
            planes = na_scale__copy_planes(source)
            list   = planes[axis]
            index  = list.each_index.min_by { |position| (list[position] - active[:u]).abs }

            if index.nil?
                list << value
            else
                list[index] = value
            end

            @na_sc_plane_drag = nil
            na_scale__save_planes(planes, NA_SCALE_OP_PLANE)
            @na_sc_active_plane = { :axis => axis, :u => value }

            low, high = Na__NobleDrawingTools.Na__ScalePlanes__DistancesMm(frame, axis, value)
            na_scale__say("#{axis.to_s.upcase} plane set at #{low} | #{high} mm")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remove One Plane — the One Under the Cursor, or the Active One
        # ------------------------------------------------------------
        # A centre plane has nothing to remove, and with Stretch Planes on the
        # axis has to stretch somewhere, so it stays and says so. The last plane
        # placed on an axis leaves the centre plane back in its place.
        # ------------------------------------------------------------
        def na_scale__remove_plane(axis, value)
            if na_scale__centre_plane?(axis)
                back = na_scale__stretch_only? ? 'Deep Stretch always stretches somewhere' : 'or SHIFT+TAB goes back to scaling'
                na_scale__say("That is #{axis.to_s.upcase}'s centre plane: it stays while Planes is on. Drag it to move it, #{back}")
                return false
            end

            planes = na_scale__copy_planes(@na_sc_planes || Na__NobleDrawingTools.Na__ScalePlanes__Empty)
            list   = planes[axis]
            index  = list.each_index.min_by { |position| (list[position] - value).abs }
            return false if index.nil?

            list.delete_at(index)
            removed = na_scale__save_planes(planes, NA_SCALE_OP_REMOVE)

            @na_sc_active_plane = nil
            @na_sc_focus        = nil if @na_sc_focus == :plane
            na_scale__say(list.empty? ? "#{axis.to_s.upcase} plane removed — back to its centre plane" : "#{axis.to_s.upcase} plane removed — #{list.length} left on that axis") if removed
            removed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remove the Plane Under the Cursor, or Else the Selected One
        # ------------------------------------------------------------
        # True when there was one to act on, even if it refused to go (a
        # centre plane says why). False when no plane is chosen. A plane that
        # is switched off is not on show, so it is not there to be chosen.
        # ------------------------------------------------------------
        def na_scale__remove_chosen_plane
            return false unless na_scale__planes_editable?

            hover = @na_sc_hover

            if hover && hover[:kind] == :handle
                @na_sc_hover = nil                                            # <-- First: what the removal says is only kept while the hover it was said over lasts
                na_scale__remove_plane(hover[:axis], hover[:u])
                return true
            end

            return false unless @na_sc_focus == :plane && @na_sc_active_plane

            na_scale__remove_plane(@na_sc_active_plane[:axis], @na_sc_active_plane[:u])
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remove Every Plane Saved on the Object; Returns How Many Went
        # nil when there is no object to clear. Centre planes are not saved, so
        # they are not counted, and they are all that is left.
        # ------------------------------------------------------------
        def na_scale__clear_planes
            return nil unless @na_sc_frame

            count = Na__NobleDrawingTools.Na__ScalePlanes__Total(Na__NobleDrawingTools.Na__ScalePlanes__WithoutCentres(@na_sc_frame, @na_sc_planes))
            return 0 if count.zero?

            na_scale__cancel_plane_drag
            na_scale__save_planes(Na__NobleDrawingTools.Na__ScalePlanes__Empty, NA_SCALE_OP_CLEAR)
            @na_sc_active_plane = nil
            count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Did the Click Before This Double-Click Just Place That Plane?
        # The first click of a double-click on a centre line drops a plane;
        # the double-click must not then take it straight back off.
        # ------------------------------------------------------------
        def na_scale__just_placed?(handle)
            placed = @na_sc_last_placed
            return false unless placed && handle
            return false unless placed[:axis] == handle[:axis]
            return false unless (Time.now - placed[:at]).to_f < 0.6

            na_scale__same_plane?(handle[:axis], placed[:u], handle[:u])
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Drawing
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Planes, the Centre Lines and the Plane on Offer
        # ------------------------------------------------------------
        # field, when given, is the grip drag in progress: each plane is drawn
        # where that stretch is taking it, across the new box, and the centre
        # lines are left out because nothing can be placed mid-drag. A plane
        # on an axis that is not stretching only gets an outline.
        #
        # With Stretch Planes off this is only reached for CTRL's offer, and
        # draws just that: the plane under the cursor and the line it rides.
        # ------------------------------------------------------------
        def na_scale__draw_planes(view, field = nil)
            frame = @na_sc_frame
            return unless frame

            unless na_scale__planes_on?
                return unless !field && na_scale__ctrl_offer?

                na_scale__draw_centre_line(view, @na_sc_hover[:axis], @na_sc_hover)
                na_scale__draw_plane_offer(view)
                return
            end

            planes = na_scale__shown_planes
            mins, maxs = field ? Na__NobleDrawingTools.Na__ScaleField__Box(field, frame) : [nil, nil]
            moved  = field ? Na__NobleDrawingTools.Na__ScaleField__PlanesAfter(field, planes) : planes
            hot    = @na_sc_hover
            handed = !field && na_scale__planes_editable?                     # <-- Mid-drag nothing can be placed

            NA_SCALE_AXES.each_with_index do |axis, n|
                next unless frame[:usable][n]

                na_scale__draw_centre_line(view, axis, hot) if handed

                (moved[axis] || []).each_with_index do |value, index|
                    quad = Na__NobleDrawingTools.Na__ScalePlanes__Quad(frame, axis, value, 0.08, mins, maxs)

                    if field && field[axis][:mode] != :stretch
                        Na__NobleDrawingTools.Na__ScalePreview__DrawIdlePlane(view, quad, axis)
                        next
                    end

                    Na__NobleDrawingTools.Na__ScalePreview__DrawPlane(view, quad, axis, na_scale__plane_hot?(axis, index))
                end
            end

            # After every plane, so none of them is painted over the diamond of another.
            if handed
                na_scale__plane_handles(view).each do |handle|
                    Na__NobleDrawingTools.Na__ScalePreview__DrawDiamond(
                        view, handle[:screen],
                        na_scale__plane_hot?(handle[:axis], handle[:index]) ? NA_SCALE_HANDLE_HOT_PIXELS : NA_SCALE_HANDLE_PIXELS,
                        Na__NobleDrawingTools.Na__ScalePreview__AxisColor(handle[:axis])
                    )
                end
            end

            na_scale__draw_plane_offer(view) unless field
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Plane Being Held, or Under the Cursor?
        # ------------------------------------------------------------
        def na_scale__plane_hot?(axis, index)
            drag = @na_sc_plane_drag
            over = @na_sc_hover

            return true if drag && drag[:axis] == axis && (drag[:index] == index || drag[:mirror] == index)
            return true if over && over[:kind] == :handle && over[:axis] == axis && over[:index] == index

            na_scale__plane_selected?(axis, index)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This the Selected Plane: the One DEL Removes and Typing Moves?
        # ------------------------------------------------------------
        def na_scale__plane_selected?(axis, index)
            active = @na_sc_active_plane
            return false unless active && @na_sc_focus == :plane && active[:axis] == axis

            value = (na_scale__shown_planes[axis] || [])[index]
            value ? na_scale__same_plane?(axis, value, active[:u]) : false
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Axis's Centre Line, Unless It Is Seen End-On
        # A line seen end-on is a dot that cannot be clicked, so it is not
        # drawn as if it could be.
        # ------------------------------------------------------------
        def na_scale__draw_centre_line(view, axis, hot)
            ends   = Na__NobleDrawingTools.Na__ScalePlanes__CentreLine(@na_sc_frame, axis)
            screen = Na__NobleDrawingTools.Na__DrawnPreview__ScreenPoints(view, ends)
            return false unless screen && screen[0].distance(screen[1]) >= NA_SCALE_MIN_EDGE_PIXELS

            line_hot = hot && hot[:kind] == :line && hot[:axis] == axis
            Na__NobleDrawingTools.Na__ScalePreview__DrawCentreLine(view, ends[0], ends[1], axis, line_hot)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane Label Mirroring a Distance Being Typed
        # ------------------------------------------------------------
        def na_scale__draw_typed_plane_label(view)
            frame  = @na_sc_frame
            plane  = @na_sc_plane_drag ? { :axis => @na_sc_plane_drag[:axis], :u => @na_sc_plane_drag[:planes][@na_sc_plane_drag[:axis]][@na_sc_plane_drag[:index]] } :
                                         @na_sc_active_plane
            return false unless frame && plane

            Na__NobleDrawingTools.Na__ScalePreview__DrawModeCard(
                view,
                Na__NobleDrawingTools.Na__ScalePreview__Screen(view, Na__NobleDrawingTools.Na__ScalePlanes__HandlePoint(frame, plane[:axis], plane[:u])),
                "#{plane[:axis].to_s.upcase} plane  [#{@na_sc_typed}|] from the low end",
                ['Enter sets it, ESC cancels'],
                { :solid => NA_DRAWN_TEXT_LOCKED_COLOR }
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane a Click on the Centre Line Would Drop, Faint
        # ------------------------------------------------------------
        def na_scale__draw_plane_offer(view)
            offer = @na_sc_plane_hover
            return unless offer && !@na_sc_plane_drag

            frame = @na_sc_frame
            quad  = Na__NobleDrawingTools.Na__ScalePlanes__Quad(frame, offer[:axis], offer[:u], 0.08)
            Na__NobleDrawingTools.Na__ScalePreview__DrawPlane(view, quad, offer[:axis], false)

            if offer[:twin]
                twin = Na__NobleDrawingTools.Na__ScalePlanes__Quad(frame, offer[:axis], offer[:twin], 0.08)
                Na__NobleDrawingTools.Na__ScalePreview__DrawPlane(view, twin, offer[:axis], false)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Distances From Both Ends for the Plane Being Placed or Hovered
        # ------------------------------------------------------------
        # On a card: a centre plane's label stands where three planes cross,
        # and bare coloured text over them cannot be read (5.2.22).
        # ------------------------------------------------------------
        def na_scale__draw_plane_label(view)
            frame = @na_sc_frame
            return na_scale__draw_typed_plane_label(view) if na_scale__typing? && na_scale__typing_plane?

            info  =
                if @na_sc_plane_drag
                    drag = @na_sc_plane_drag
                    { :axis => drag[:axis], :u => drag[:planes][drag[:axis]][drag[:index]], :how => drag[:how], :verb => drag[:created] ? 'new' : 'moving' }
                elsif @na_sc_plane_hover
                    offer  = @na_sc_plane_hover
                    centre = na_scale__centre_plane?(offer[:axis])
                    count  = centre ? 0 : ((@na_sc_planes || {})[offer[:axis]] || []).length
                    verb   = count.zero? ? 'click to add a plane here' : "click to add plane #{count + 1} on #{offer[:axis].to_s.upcase}"
                    verb   = "#{verb}: it takes over from the centre plane" if centre
                    { :axis => offer[:axis], :u => offer[:u], :how => offer[:how], :verb => offer[:twin] ? "#{verb} (and its mirror)" : verb }
                elsif @na_sc_hover && @na_sc_hover[:kind] == :handle
                    hover = @na_sc_hover
                    { :axis => hover[:axis], :u => hover[:u], :how => nil, :verb => na_scale__centre_plane?(hover[:axis]) ? 'its centre plane: drag to move it' : 'drag to move, DEL to remove' }
                end

            return unless info

            low, high = Na__NobleDrawingTools.Na__ScalePlanes__DistancesMm(frame, info[:axis], info[:u])
            snap      = info[:how] && info[:how] != 'grid' ? "  ·  on #{info[:how]}" : ''

            Na__NobleDrawingTools.Na__ScalePreview__DrawModeCard(
                view,
                Na__NobleDrawingTools.Na__ScalePreview__Screen(view, Na__NobleDrawingTools.Na__ScalePlanes__HandlePoint(frame, info[:axis], info[:u])),
                "#{info[:axis].to_s.upcase} plane  #{low} | #{high} mm#{snap}",
                [info[:verb]],
                { :solid => Na__NobleDrawingTools.Na__ScalePreview__AxisColor(info[:axis]) }
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Where a Stretch Is Opening the Object Up, Across the New Box
        # ------------------------------------------------------------
        # The picture that says "stretch" rather than "scale": the slices either
        # side keep their size and only these bands change. Plane i parts slice
        # i from slice i + 1, so the band runs between where each of those
        # slices takes the plane (Na__ScaleField__SliceShift). On a shrink the
        # two ends swap and the band is what closes up. Drawn on top or not at
        # all: a decoration has no business being half hidden in the object.
        # ------------------------------------------------------------
        def na_scale__draw_stretch_bands(view, field, mins, maxs)
            frame = @na_sc_frame

            NA_SCALE_AXES.each_with_index do |axis, n|
                spec = field[axis]
                next unless spec && spec[:mode] == :stretch

                step = spec[:delta] / spec[:planes].length

                spec[:planes].each_with_index do |plane, index|
                    start  = plane + spec[:base] + (index * step)
                    lo     = mins.dup
                    hi     = maxs.dup
                    lo[n]  = [start, start + step].min
                    hi[n]  = [start, start + step].max

                    near, far = Na__NobleDrawingTools.Na__ScaleFrame__BoxQuads(frame, lo, hi)
                    Na__NobleDrawingTools.Na__DrawnPreview__DrawFilledBoxOnTop(view, near, far, NA_SCALE_BAND_FILL_COLOR, NA_SCALE_BAND_BORDER_COLOR)
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Line of Help Under the Mode Strip: How to Add, Move and Remove Planes
        # ------------------------------------------------------------
        # Said for the state the planes are in, so it is never a list to learn:
        # none yet, some, or CTRL held. Nothing while the bar's own tip is
        # showing, or mid-drag. top is the first y clear of the strip.
        # ------------------------------------------------------------
        def na_scale__draw_plane_hint(view, top)
            lines = na_scale__plane_hint_lines
            return false if lines.empty?

            Na__NobleDrawingTools.Na__DrawnPreview__DrawScreenText(view, NA_SCALE_BAR_ORIGIN[0], top, lines, NA_DRAWN_TEXT_ACCENT_COLOR)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Words for the Plane Hint, or [] When There Is Nothing to Say
        # ------------------------------------------------------------
        def na_scale__plane_hint_lines
            frame = @na_sc_frame
            return [] unless frame
            return [] if @na_sc_drag || @na_sc_plane_drag
            return [] if na_scale__over_controls?

            lines = na_scale__plane_hint_lines_for_object
            return lines unless frame[:loose] && !lines.empty?

            lines + ["Planes on a selection are kept while #{na_drawn__tool_title} holds it — they are not saved with the model"]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane Hint for What Is Held, Before a Selection's Note Is Added
        # ------------------------------------------------------------
        def na_scale__plane_hint_lines_for_object
            frame = @na_sc_frame

            count = Na__NobleDrawingTools.Na__ScalePlanes__Total(
                NA_SCALE_AXES.each_with_object({}) { |axis, inside| inside[axis] = Na__NobleDrawingTools.Na__ScalePlanes__Inside(frame, axis, (@na_sc_planes || {})[axis]) }
            )

            if na_scale__ctrl_offer?
                axis = @na_sc_hover[:axis].to_s.upcase
                return ["CTRL: click to add #{axis == 'X' ? 'an' : 'a'} #{axis} plane here — move nearer another centre line, or press an ARROW, for another axis",
                        'SHIFT adds a mirrored pair']
            end

            return [] unless na_scale__planes_on?                              # <-- Planes saved but switched off: the sentence over this says so, in red
            return [] if count.zero?                                           # <-- Every axis too thin to hold a plane, which the sentence says too

            chosen = @na_sc_focus == :plane ? @na_sc_active_plane : nil

            if chosen
                axis = chosen[:axis].to_s.upcase
                return ["#{axis} centre plane selected: it stays while Planes is on. Drag its diamond, or type a distance from the low end, to move it"] if na_scale__centre_plane?(chosen[:axis])

                return ["#{axis} plane selected: DEL removes it, or type a distance from the low end to move it",
                        'Click a centre line, or hold CTRL, to add another · ESC or a click off the object lets go of this one']
            end

            if na_scale__usable_axes.all? { |axis| na_scale__centre_plane?(axis) }
                return ['Each plane starts at the centre of its axis: drag a diamond to move it',
                        'Or click a dashed centre line, or hold CTRL over the object, to place your own. It takes over from the centre plane']
            end

            ["#{count} stretch plane#{count == 1 ? '' : 's'} — click a centre line, or hold CTRL, to add another",
             'Drag a diamond to move a plane · DEL or double-click removes it · right-click: Clear Stretch Planes']
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnScalePlanes module

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DEEP SCALE STRETCH PLANES (TOOL HALF)
# =============================================================================
