# =============================================================================
# NA INSERT PRIMATIVES - DEEP SCALE STRETCH PLANES (TOOL HALF)
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnScale__Planes__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnScalePlanes
# AUTHOR     : Noble Architecture
# PURPOSE    : Place, drag, mirror and remove stretch planes on the object
#              Deep Scale is holding, and draw them
# CREATED    : 2026
#
# DESCRIPTION:
# - TWO WAYS TO ADD A PLANE, and every one ADDS (5.2.6; until then a click
#   without CTRL replaced the axis's planes, which read as "only one plane"):
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
# - Press on a plane's diamond to drag it (SHIFT moves its mirror with it).
#   DEL, or a double-click on the diamond, removes it. Right after placing
#   or moving one, a typed value sets its distance from the low end. Clear
#   Stretch Planes (right-click menu) removes the lot.
# - A line of help under the handle bar says which of these applies right
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

module Na__InsertPrimatives

    # =============================================================================
    # MODULE | Deep Scale Stretch Planes
    # =============================================================================

    module DrawnScalePlanes

        NA_SCALE_HANDLE_HIT_PX = 9.0
        NA_SCALE_LINE_HIT_PX   = 9.0
        NA_SCALE_CTRL_REACH_PX = 40.0                                         # <-- CTRL offers a plane this far outside the object's outline on screen

        # -----------------------------------------------------------------------------
        # REGION | Finding Planes Under the Cursor
        # -----------------------------------------------------------------------------

        # FUNCTION | The Planes to Show — the Working Copy Mid-Drag, Else the Saved Ones
        # ------------------------------------------------------------
        def na_scale__shown_planes
            return @na_sc_plane_drag[:planes] if @na_sc_plane_drag

            @na_sc_planes || Na__InsertPrimatives.Na__ScalePlanes__Empty
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
                    world  = Na__InsertPrimatives.Na__ScalePlanes__HandlePoint(frame, axis, value)
                    screen = Na__InsertPrimatives.Na__ScalePreview__Screen(view, world)
                    next unless screen

                    handles << { :axis => axis, :index => index, :u => value, :world => world, :screen => screen }
                end
            end

            handles
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

                ends   = Na__InsertPrimatives.Na__ScalePlanes__CentreLine(frame, axis)
                screen = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, ends)
                next unless screen
                next if screen[0].distance(screen[1]) < NA_SCALE_MIN_EDGE_PIXELS      # <-- Seen end-on: a dot, not a line to drop a plane on

                dist = Na__InsertPrimatives.Na__ScalePreview__SegmentDistance(x, y, screen[0], screen[1])
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
            return nil if frame[:loose]                                       # <-- Nowhere to keep a plane on loose geometry

            corners = Na__InsertPrimatives.Na__ScaleFrame__BoxQuads(frame, frame[:min], frame[:max]).flatten
            screen  = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, corners)
            return nil unless screen && Na__InsertPrimatives.Na__ScalePreview__Sane?(screen)

            reach = NA_SCALE_CTRL_REACH_PX
            return nil if x < screen.map(&:x).min - reach || x > screen.map(&:x).max + reach
            return nil if y < screen.map(&:y).min - reach || y > screen.map(&:y).max + reach

            best      = nil
            best_dist = nil

            NA_SCALE_AXES.each_with_index do |axis, n|
                next unless frame[:usable][n]
                next if @na_axis_lock && @na_axis_lock != axis

                ends = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, Na__InsertPrimatives.Na__ScalePlanes__CentreLine(frame, axis))
                next unless ends && ends[0].distance(ends[1]) >= NA_SCALE_MIN_EDGE_PIXELS

                dist = Na__InsertPrimatives.Na__ScalePreview__SegmentDistance(x, y, ends[0], ends[1])
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
            snapped = Na__InsertPrimatives.Na__ScalePlanes__SnapValue(view, @na_sc_frame, axis, @na_ip, x, y)
            return nil unless snapped

            [Na__InsertPrimatives.Na__ScalePlanes__Clamp(@na_sc_frame, axis, snapped[0]), snapped[1]]
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
            copy = Na__InsertPrimatives.Na__ScalePlanes__Empty
            NA_SCALE_AXES.each { |axis| copy[axis] = (planes[axis] || []).map(&:to_f) }
            copy
        end
        # ---------------------------------------------------------------

        # FUNCTION | Press on a Centre Line, or With CTRL — Add a Plane and Hold It
        # ------------------------------------------------------------
        # Always added to the planes the axis already has. One click on a
        # fresh object is the first plane; the next click is the second.
        # ------------------------------------------------------------
        def na_scale__begin_new_plane(view, axis, x, y)
            snapped = na_scale__plane_snap(view, axis, x, y)
            return false unless snapped

            value, how = snapped
            planes     = na_scale__copy_planes(@na_sc_planes || Na__InsertPrimatives.Na__ScalePlanes__Empty)
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
            planes = na_scale__copy_planes(@na_sc_planes || Na__InsertPrimatives.Na__ScalePlanes__Empty)
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
            drag[:moved]  = true if travelled >= Na__InsertPrimatives::DrawnToolShared::NA_DRAWN_DRAG_MIN_PX
            return false unless drag[:moved]

            snapped = na_scale__plane_snap(view, drag[:axis], x, y)
            return false unless snapped

            value, how = snapped
            list       = drag[:planes][drag[:axis]]
            list[drag[:index]] = value
            drag[:how] = how

            if drag[:mirror]
                list[drag[:mirror]] = Na__InsertPrimatives.Na__ScalePlanes__Clamp(
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
        # the first half of a double-click, or a look, not a decision.
        # ------------------------------------------------------------
        def na_scale__release_plane_drag(view)
            drag = @na_sc_plane_drag
            return false unless drag

            @na_sc_plane_drag = nil
            return true unless drag[:created] || drag[:moved]

            value = drag[:planes][drag[:axis]][drag[:index]]
            na_scale__save_planes(drag[:planes], NA_SCALE_OP_PLANE)

            @na_sc_active_plane = { :axis => drag[:axis], :u => value }
            @na_sc_last_placed  = { :at => Time.now, :axis => drag[:axis], :u => value } if drag[:created]

            low, high = Na__InsertPrimatives.Na__ScalePlanes__DistancesMm(@na_sc_frame, drag[:axis], value)
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
        def na_scale__save_planes(planes, op_name)
            frame = @na_sc_frame
            return false unless frame
            return false if frame[:loose]

            tidy = Na__InsertPrimatives.Na__ScalePlanes__Prune(planes, frame[:min], frame[:max])   # <-- Orphans go whenever the planes are written
            NA_SCALE_AXES.each_with_index do |axis, n|
                tidy[axis] = Na__InsertPrimatives.Na__ScalePlanes__Tidy(tidy[axis], frame, n)
            end

            saved = Na__InsertPrimatives.Na__ScaleCommit__SavePlanes(Sketchup.active_model, frame[:definition], tidy, op_name)
            @na_sc_planes = tidy if saved
            saved
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Distance From the Low End Moves the Active Plane
        # ------------------------------------------------------------
        def na_scale__type_plane(text, view)
            active = @na_sc_active_plane
            frame  = @na_sc_frame
            raise ArgumentError, 'place or click a plane before typing its position' unless active && frame

            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'a plane takes one distance, from the low end of the object' if tokens.length > 1

            axis    = active[:axis]
            n       = NA_SCALE_AXIS_INDEX[axis]
            scale   = frame[:scales][n]
            current = (active[:u] - frame[:min][n]) * scale
            along   = Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(tokens[0], current)

            unless along > 0.0 && along < frame[:world_lengths][n]
                raise ArgumentError, "a #{axis.to_s.upcase} plane has to sit inside the object — 0 to #{Na__InsertPrimatives.Na__DrawnFormat__Mm(frame[:world_lengths][n])} mm from the low end"
            end

            value  = frame[:min][n] + (along / scale)
            source = @na_sc_plane_drag ? @na_sc_plane_drag[:planes] : (@na_sc_planes || Na__InsertPrimatives.Na__ScalePlanes__Empty)
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

            low, high = Na__InsertPrimatives.Na__ScalePlanes__DistancesMm(frame, axis, value)
            na_scale__say("#{axis.to_s.upcase} plane set at #{low} | #{high} mm")
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remove One Plane — the One Under the Cursor, or the Active One
        # ------------------------------------------------------------
        def na_scale__remove_plane(axis, value)
            planes = na_scale__copy_planes(@na_sc_planes || Na__InsertPrimatives.Na__ScalePlanes__Empty)
            list   = planes[axis]
            index  = list.each_index.min_by { |position| (list[position] - value).abs }
            return false if index.nil?

            list.delete_at(index)
            removed = na_scale__save_planes(planes, NA_SCALE_OP_REMOVE)

            @na_sc_active_plane = nil
            @na_sc_focus        = nil if @na_sc_focus == :plane
            na_scale__say("#{axis.to_s.upcase} plane removed — #{list.length} left on that axis") if removed
            removed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remove Every Plane Saved on the Object; Returns How Many Went
        # nil when there is no object to clear.
        # ------------------------------------------------------------
        def na_scale__clear_planes
            return nil unless @na_sc_frame

            count = Na__InsertPrimatives.Na__ScalePlanes__Total(@na_sc_planes)
            return 0 if count.zero?

            na_scale__cancel_plane_drag
            na_scale__save_planes(Na__InsertPrimatives.Na__ScalePlanes__Empty, NA_SCALE_OP_CLEAR)
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
        # lines are left out because nothing can be placed mid-drag.
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
                na_scale__draw_plane_label(view)
                return
            end

            planes = na_scale__shown_planes
            mins, maxs = field ? Na__InsertPrimatives.Na__ScaleField__Box(field, frame) : [nil, nil]
            moved  = field ? Na__InsertPrimatives.Na__ScaleField__PlanesAfter(field, planes) : planes
            hot    = @na_sc_hover

            NA_SCALE_AXES.each_with_index do |axis, n|
                next unless frame[:usable][n]

                na_scale__draw_centre_line(view, axis, hot) unless field

                (moved[axis] || []).each_with_index do |value, index|
                    held  = @na_sc_plane_drag && @na_sc_plane_drag[:axis] == axis &&
                            (@na_sc_plane_drag[:index] == index || @na_sc_plane_drag[:mirror] == index)
                    over  = hot && hot[:kind] == :handle && hot[:axis] == axis && hot[:index] == index
                    quad  = Na__InsertPrimatives.Na__ScalePlanes__Quad(frame, axis, value, 0.08, mins, maxs)
                    Na__InsertPrimatives.Na__ScalePreview__DrawPlane(view, quad, axis, held || over)

                    next if field

                    screen = Na__InsertPrimatives.Na__ScalePreview__Screen(
                        view, Na__InsertPrimatives.Na__ScalePlanes__HandlePoint(frame, axis, value)
                    )
                    next unless screen

                    Na__InsertPrimatives.Na__ScalePreview__DrawDiamond(
                        view, screen,
                        (held || over) ? NA_SCALE_HANDLE_HOT_PIXELS : NA_SCALE_HANDLE_PIXELS,
                        Na__InsertPrimatives.Na__ScalePreview__AxisColor(axis)
                    )
                end
            end

            na_scale__draw_plane_offer(view) unless field
            na_scale__draw_plane_label(view) unless field
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Axis's Centre Line, Unless It Is Seen End-On
        # A line seen end-on is a dot that cannot be clicked, so it is not
        # drawn as if it could be.
        # ------------------------------------------------------------
        def na_scale__draw_centre_line(view, axis, hot)
            ends   = Na__InsertPrimatives.Na__ScalePlanes__CentreLine(@na_sc_frame, axis)
            screen = Na__InsertPrimatives.Na__DrawnPreview__ScreenPoints(view, ends)
            return false unless screen && screen[0].distance(screen[1]) >= NA_SCALE_MIN_EDGE_PIXELS

            line_hot = hot && hot[:kind] == :line && hot[:axis] == axis
            Na__InsertPrimatives.Na__ScalePreview__DrawCentreLine(view, ends[0], ends[1], axis, line_hot)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane Label Mirroring a Distance Being Typed
        # ------------------------------------------------------------
        def na_scale__draw_typed_plane_label(view)
            frame  = @na_sc_frame
            plane  = @na_sc_plane_drag ? { :axis => @na_sc_plane_drag[:axis], :u => @na_sc_plane_drag[:planes][@na_sc_plane_drag[:axis]][@na_sc_plane_drag[:index]] } :
                                         @na_sc_active_plane
            return false unless frame && plane

            Na__InsertPrimatives.Na__ScalePreview__DrawWorldLabel(
                view,
                Na__InsertPrimatives.Na__ScalePlanes__HandlePoint(frame, plane[:axis], plane[:u]),
                ["#{plane[:axis].to_s.upcase} plane  [#{@na_sc_typed}|] from the low end", 'Enter sets it, ESC cancels'],
                14, -40, NA_DRAWN_TEXT_LOCKED_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Plane a Click on the Centre Line Would Drop, Faint
        # ------------------------------------------------------------
        def na_scale__draw_plane_offer(view)
            offer = @na_sc_plane_hover
            return unless offer && !@na_sc_plane_drag

            frame = @na_sc_frame
            quad  = Na__InsertPrimatives.Na__ScalePlanes__Quad(frame, offer[:axis], offer[:u], 0.08)
            Na__InsertPrimatives.Na__ScalePreview__DrawPlane(view, quad, offer[:axis], false)

            if offer[:twin]
                twin = Na__InsertPrimatives.Na__ScalePlanes__Quad(frame, offer[:axis], offer[:twin], 0.08)
                Na__InsertPrimatives.Na__ScalePreview__DrawPlane(view, twin, offer[:axis], false)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Distances From Both Ends for the Plane Being Placed or Hovered
        # ------------------------------------------------------------
        def na_scale__draw_plane_label(view)
            frame = @na_sc_frame
            return na_scale__draw_typed_plane_label(view) if na_scale__typing? && na_scale__typing_plane?

            info  =
                if @na_sc_plane_drag
                    drag = @na_sc_plane_drag
                    { :axis => drag[:axis], :u => drag[:planes][drag[:axis]][drag[:index]], :how => drag[:how], :verb => drag[:created] ? 'new' : 'moving' }
                elsif @na_sc_plane_hover
                    offer = @na_sc_plane_hover
                    count = ((@na_sc_planes || {})[offer[:axis]] || []).length
                    verb  = count.zero? ? 'click to add a plane here' : "click to add plane #{count + 1} on #{offer[:axis].to_s.upcase}"
                    { :axis => offer[:axis], :u => offer[:u], :how => offer[:how], :verb => offer[:twin] ? "#{verb} (and its mirror)" : verb }
                elsif @na_sc_hover && @na_sc_hover[:kind] == :handle
                    hover = @na_sc_hover
                    { :axis => hover[:axis], :u => hover[:u], :how => nil, :verb => 'drag to move, DEL to remove' }
                end

            return unless info

            low, high = Na__InsertPrimatives.Na__ScalePlanes__DistancesMm(frame, info[:axis], info[:u])
            snap      = info[:how] && info[:how] != 'grid' ? "  ·  on #{info[:how]}" : ''
            lines     = ["#{info[:axis].to_s.upcase} plane  #{low} | #{high} mm#{snap}", info[:verb]]

            Na__InsertPrimatives.Na__ScalePreview__DrawWorldLabel(
                view,
                Na__InsertPrimatives.Na__ScalePlanes__HandlePoint(frame, info[:axis], info[:u]),
                lines, 14, -40,
                Na__InsertPrimatives.Na__ScalePreview__AxisColor(info[:axis])
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Line of Help Under the Bar: How to Add, Move and Remove Planes
        # ------------------------------------------------------------
        # Said for the state the planes are in, so it is never a list to learn:
        # none yet, some, CTRL held, or an object with planes while the switch
        # is off. Nothing while the bar's own tip is showing, or mid-drag.
        # ------------------------------------------------------------
        def na_scale__draw_plane_hint(view)
            lines = na_scale__plane_hint_lines
            return false if lines.empty?

            bar = @na_sc_bar || []
            top = bar.empty? ? NA_SCALE_BAR_ORIGIN[1] + NA_SCALE_BAR_HEIGHT : bar.map { |button| button[:rect][3] }.max
            Na__InsertPrimatives.Na__DrawnPreview__DrawScreenText(view, NA_SCALE_BAR_ORIGIN[0], top + 22, lines, NA_DRAWN_TEXT_ACCENT_COLOR)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Words for the Plane Hint, or [] When There Is Nothing to Say
        # ------------------------------------------------------------
        def na_scale__plane_hint_lines
            frame = @na_sc_frame
            return [] unless frame
            return [] if @na_sc_drag || @na_sc_plane_drag
            return [] if @na_sc_hover && @na_sc_hover[:kind] == :bar

            if frame[:loose]
                wanted = @na_ctrl_held || Na__InsertPrimatives.Na__ToolOptions__Enabled?(NA_SCALE_OPTION_PLANES)
                return [] unless wanted

                return ['Loose geometry scales whole: stretch planes are saved on a group or component, and this has neither',
                        'Make it a group (right-click > Make Group) to stretch it at planes']
            end

            count = Na__InsertPrimatives.Na__ScalePlanes__Total(
                NA_SCALE_AXES.each_with_object({}) { |axis, inside| inside[axis] = Na__InsertPrimatives.Na__ScalePlanes__Inside(frame, axis, (@na_sc_planes || {})[axis]) }
            )

            if na_scale__ctrl_offer?
                axis = @na_sc_hover[:axis].to_s.upcase
                return ["CTRL: click to add #{axis == 'X' ? 'an' : 'a'} #{axis} plane here — move nearer another centre line, or press an ARROW, for another axis",
                        'SHIFT adds a mirrored pair']
            end

            unless na_scale__planes_on?
                return [] if count.zero?

                return ["#{frame[:name]} has #{count} stretch plane#{count == 1 ? '' : 's'} — SHIFT+TAB (or Planes) switches them on so the grips stretch at them"]
            end

            if count.zero?
                return ['Stretch Planes: click a dashed centre line to drop a plane — or hold CTRL anywhere over the object',
                        'Drag it into place; it snaps to edges and faces. SHIFT drops a mirrored pair']
            end

            ["#{count} stretch plane#{count == 1 ? '' : 's'} — click a centre line, or hold CTRL, to add another",
             'Drag a diamond to move a plane · DEL or double-click removes it · right-click: Clear Stretch Planes']
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnScalePlanes module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP SCALE STRETCH PLANES (TOOL HALF)
# =============================================================================
