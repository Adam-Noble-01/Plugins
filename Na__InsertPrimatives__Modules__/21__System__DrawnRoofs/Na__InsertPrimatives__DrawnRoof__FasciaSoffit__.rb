# =============================================================================
# NA INSERT PRIMATIVES - DRAWN ROOF FASCIA AND SOFFIT STAGES
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnRoof__FasciaSoffit__.rb
# NAMESPACE  : Na__InsertPrimatives::DrawnRoofFasciaSoffit
# AUTHOR     : Noble Architecture
# PURPOSE    : The fascia and soffit stages behind the roof tools' Fascia & Soffit option
# CREATED    : 2026
#
# DESCRIPTION:
# - Mixed into DrawnRoofToolBase, after DrawnToolShared, so its mouse, cursor
#   and step-back methods sit in front of the shared ones and hand back to
#   them with super outside their own stages.
# - With Fascia & Soffit switched off in the popup submenu none of this runs
#   and both roof tools behave exactly as they did before. It is ON by default.
#
# THE GESTURE, END TO END:
#   1  drag the rectangle on the top of the wall        (:picking_b, the wall line)
#   2  pull up the fascia and click, or type 225        (:picking_fascia)
#   3  drag out the soffit and click, or type 300       (:picking_soffit)
#   4  pull up the roof or type a pitch, as before      (:picking_depth)
#   The roof is pitched over the EAVES, the wall line plus a soffit each side,
#   and sits on top of the fascia. See DrawnRoofGeometry for the build.
#
# THE SOFFIT DRAG CUTS A PLANE:
# - Deep Chamfer's lesson again. Looking down on the roof, or up at the eaves,
#   the cursor ray is cut with the plan plane at the fascia top, so the eaves
#   edge sits under the cursor. At eye level that plane is edge-on, so the ray
#   is cut with an upright plane through the middle of the wall line, facing
#   the camera. The choice follows the camera, not the ray, so it cannot flip
#   in the middle of a drag.
# - The soffit is how far the cursor is OUTSIDE the wall line, taken from the
#   side it is furthest past. Inside the line it reads nothing, not a negative.
#
# MEASUREMENTS BOX:
#   fascia stage   225 | 225,300 (on to the pitch) | 225,300,35 (builds it)
#   soffit stage   300 | 300,35 (builds it)
#   pitch stage    35 | 3000mm, as before · 250s or 250f change the plinth and stay
#   after drawing  250f | 400s | 250f,400s correct the plinth; the pitch is held
#   A letter names the value wherever it is typed: 300s,225 is a 225 fascia and a
#   300 soffit. Bare numbers are mm here; only the pitch slot reads degrees.
#
# COORDINATES:
# - World space throughout, like every drawn tool: the wall rectangle, the pick
#   rays, the preview and the points added into a group pinned to the world
#   identity. No edit_transform anywhere.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnToolShared__'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnRoofGeometry__'

module Na__InsertPrimatives

    # =============================================================================
    # MODULE | Drawn Roof Fascia and Soffit Stages
    # =============================================================================

    module DrawnRoofFasciaSoffit

        # -----------------------------------------------------------------------------
        # REGION | Stage Constants
        # -----------------------------------------------------------------------------

        NA_ROOF_PLINTH_STAGES  = [:picking_fascia, :picking_soffit].freeze
        NA_ROOF_PLINTH_SLOTS   = [:fascia, :soffit, :pitch].freeze

        # A trailing f or s names the value: 225f, 300s, +50f, 0.3m s. Longest
        # alternatives first so "300soffit" is not read as "300soffi" plus t.
        # No dimension or pitch entry ends in either letter, so nothing the
        # roofs already accepted is read differently.
        NA_ROOF_PLINTH_SUFFIX  = /\A(.*?)\s*(fascia|soffit|f|s)\z/i

        # Below this the camera looks too flat across the plan plane to cut it
        # usefully, and the upright plane takes over.
        NA_ROOF_SOFFIT_GRAZING = 0.2

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Option and Stage State
        # -----------------------------------------------------------------------------

        # FUNCTION | Create the Plinth State
        # ------------------------------------------------------------
        def na_roof__init_plinth_state
            @na_roof_plinth_on = false                                        # <-- This drag is building a plinth
            @na_roof_fascia    = 0.0                                          # <-- Internal inches; kept after a build for revise
            @na_roof_soffit    = 0.0
            @na_roof_stage_x   = 0                                            # <-- Where the current stage was entered, for the double-click echo
            @na_roof_stage_y   = 0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is Fascia & Soffit Switched On in the Popup?
        # ------------------------------------------------------------
        def na_roof__plinth_option?
            Na__InsertPrimatives.Na__ToolOptions__Enabled?('roof_fascia_soffit')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Tool in the Fascia or Soffit Stage?
        # ------------------------------------------------------------
        def na_roof__plinth_stage?
            NA_ROOF_PLINTH_STAGES.include?(@na_state)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Does the Roof Being Drawn, or Just Built, Stand on a Plinth?
        # ------------------------------------------------------------
        # Idle: whatever the roof on offer for revise was built with, so a
        # plinth roof is corrected as one even after the option is switched
        # off. Setting out the wall: the option, so a W,L,pitch typed straight
        # in builds with one. Past that: what this drag decided when it left
        # the wall line, so a toggle mid-drag cannot pull the plinth out from
        # under the preview.
        # ------------------------------------------------------------
        def na_roof__plinth_live?
            case @na_state
            when :idle      then (@na_last_record && @na_last_record[:plinth]) ? true : false
            when :picking_b then na_roof__plinth_option?
            else                 @na_roof_plinth_on == true
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Plinth Box Part of the Preview Right Now?
        # ------------------------------------------------------------
        def na_roof__plinth_drawn?
            na_roof__plinth_stage? || (@na_state == :picking_depth && @na_roof_plinth_on == true)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Live Fascia and Soffit as the Builder Takes Them
        # ------------------------------------------------------------
        def na_roof__plinth_spec
            { :fascia => @na_roof_fascia.to_f.abs, :soffit => @na_roof_soffit.to_f.abs }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load the Last Plinth Built, for a Roof Typed Straight In
        # ------------------------------------------------------------
        def na_roof__prime_plinth_from_memory
            memory          = Na__InsertPrimatives.Na__DrawnRoof__PlinthMemory
            @na_roof_fascia = memory[:fascia].to_f
            @na_roof_soffit = memory[:soffit].to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Rectangle the Roof Itself Is Built On
        # ------------------------------------------------------------
        # Without a plinth, the wall rectangle as drawn. With one, the eaves:
        # a soffit out on every side and a fascia up. Every piece of roof
        # maths goes through here, so the pitch is always measured over the
        # span the roof really has.
        # ------------------------------------------------------------
        def na_roof__footprint(origin = @na_point_a, u_len = na_drawn__signed_u, v_len = na_drawn__signed_v)
            unless na_roof__plinth_live?
                return { :base_origin => origin, :origin => origin, :u => u_len, :v => v_len, :fascia => 0.0, :soffit => 0.0 }
            end

            Na__InsertPrimatives.Na__DrawnRoof__PlinthFootprint(
                origin, @na_plane_key, u_len, v_len, @na_roof_fascia, @na_roof_soffit
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Cancelled Drag Drops the Plinth Decision With It
        # The fascia and soffit values stay: they are what a revise acts on.
        # ------------------------------------------------------------
        def na_drawn__on_pick_state_reset
            super
            @na_roof_plinth_on = false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Stage Transitions
        # -----------------------------------------------------------------------------

        # FUNCTION | Remember Where the Stage Began
        # A double click lands its second half here; see onLButtonDoubleClick.
        # ------------------------------------------------------------
        def na_roof__mark_stage_entry
            @na_roof_stage_x = @na_last_mouse_x
            @na_roof_stage_y = @na_last_mouse_y
        end
        # ---------------------------------------------------------------

        # FUNCTION | Wall Line Settled — Pull Up the Fascia
        # ------------------------------------------------------------
        def na_roof__begin_fascia_stage(view)
            @na_roof_plinth_on = true
            @na_roof_fascia    = 0.0
            @na_roof_soffit    = 0.0
            @na_size_d         = 0.0
            @na_sign_d         = 1.0
            @na_state          = :picking_fascia
            na_roof__mark_stage_entry
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Fascia Settled — Drag Out the Soffit
        # ------------------------------------------------------------
        def na_roof__begin_soffit_stage(view)
            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_roof_fascia)
                UI.beep
                Sketchup::set_status_text('The fascia has no height yet — pull up and click, or type one such as 225', SB_PROMPT)
                return false
            end

            @na_roof_soffit = 0.0
            @na_state       = :picking_soffit
            na_roof__mark_stage_entry
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Soffit Settled — On to the Roof's Own Rise
        # A soffit of nothing is allowed: a flush eaves, the plinth straight up
        # off the wall face.
        # ------------------------------------------------------------
        def na_roof__begin_pitch_stage(view)
            @na_state  = :picking_depth
            @na_size_d = 0.0
            @na_sign_d = 1.0
            na_roof__mark_stage_entry
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Settle Whichever Plinth Stage Is Live
        # ------------------------------------------------------------
        def na_roof__advance_plinth_stage(view)
            return na_roof__begin_soffit_stage(view) if @na_state == :picking_fascia

            na_roof__begin_pitch_stage(view)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Click the Second Half of the One That Opened the Stage?
        # ------------------------------------------------------------
        def na_roof__stage_echo?(x, y)
            travelled = (x.to_f - @na_roof_stage_x.to_f).abs + (y.to_f - @na_roof_stage_y.to_f).abs
            travelled < DrawnToolShared::NA_DRAWN_DRAG_MIN_PX
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP From the Pitch Stage Goes Back to the Soffit
        # ------------------------------------------------------------
        def na_drawn__stage_before_depth
            return super unless @na_roof_plinth_on == true

            :picking_soffit
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP Steps Back: Soffit, Fascia, Then the Wall Line
        # ------------------------------------------------------------
        # The shared step-back peels typed pins first, but those belong to the
        # wall line's stage; here BKSP just goes back a stage.
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            return super unless na_roof__plinth_stage?

            if @na_state == :picking_soffit
                @na_state       = :picking_fascia
                @na_roof_soffit = 0.0
            else
                @na_state          = :picking_b
                @na_roof_plinth_on = false
                @na_roof_fascia    = 0.0
            end

            na_roof__mark_stage_entry
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Mouse and Enter
        # -----------------------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Settle the Fascia or the Soffit
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            return super unless na_roof__plinth_stage?

            @na_vcb_typing_active = false
            @na_drag_press_active = false
            na_drawn__sync_modifier(flags)
            na_drawn__update_cursor(view, x, y)
            na_roof__advance_plinth_stage(view)

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOUBLE CLICK | Settle, Unless It Is the Last Click's Echo
        # ------------------------------------------------------------
        # A double click delivers Down, Up, DoubleClick: the Down has already
        # moved on a stage, so the DoubleClick arrives in the NEXT one with
        # nothing dragged yet. Settling that would beep at a fascia of nothing,
        # or build a roof of no rise. It is ignored when it lands where the
        # stage began.
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            return super unless na_roof__plinth_drawn?

            na_drawn__sync_modifier(flags)
            return true if na_roof__stage_echo?(x, y)
            return super unless na_roof__plinth_stage?                        # <-- The pitch stage builds as it always has

            na_drawn__update_cursor(view, x, y)
            na_roof__advance_plinth_stage(view)

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # ON RETURN | Enter Settles the Fascia or the Soffit
        # ------------------------------------------------------------
        def onReturn(view)
            return super unless na_roof__plinth_stage?

            na_roof__advance_plinth_stage(view)

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Cursor Tracking
        # -----------------------------------------------------------------------------

        # FUNCTION | Measure the Fascia or the Soffit from the Cursor
        # ------------------------------------------------------------
        # CTRL takes the InputPoint in both stages, so the fascia can be run up
        # to an existing gutter line or the soffit out to an existing verge;
        # CTRL+SHIFT rounds that. A frame nothing could be projected in keeps
        # the last good value.
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            return super unless na_roof__plinth_stage?

            @na_last_mouse_x = x
            @na_last_mouse_y = y

            source =
                if @na_ctrl_held
                    na_drawn__input_point_position(view, x, y)
                elsif @na_state == :picking_fascia
                    na_drawn__depth_point_from_ray(view, x, y)
                else
                    na_roof__soffit_plane_point(view, x, y)
                end
            return false unless source && @na_point_a

            @na_cursor_raw = source

            if @na_state == :picking_fascia
                na_roof__measure_fascia(source)
            else
                na_roof__measure_soffit(source)
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Fascia Is the Rise Above the Wall Line, Never Below It
        # ------------------------------------------------------------
        # Rounded as a distance rather than as a point, the way the stair rounds
        # its run, so a wall line set out on a CTRL vertex still gets a fascia
        # of a whole grid step. The snapped point is the source slid by what
        # the rounding took off, which is where the CTRL+SHIFT mark draws.
        # ------------------------------------------------------------
        def na_roof__measure_fascia(source)
            _u_axis, _v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_key)

            travel = (source - @na_point_a).dot(n_axis).to_f
            fascia = na_drawn__snap_distance(travel).to_f
            fascia = 0.0 if fascia < 0.0

            @na_roof_fascia    = fascia
            @na_cursor_snapped = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(source, n_axis, fascia - travel)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Soffit Is How Far Outside the Wall Line the Cursor Is
        # ------------------------------------------------------------
        def na_roof__measure_soffit(source)
            reach, axis, direction = na_roof__soffit_reach(source)

            soffit = na_drawn__snap_distance(reach).to_f
            soffit = 0.0 if soffit < 0.0

            @na_roof_soffit    = soffit
            @na_cursor_snapped = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(source, axis, direction * (soffit - reach))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Distance Past the Wall Line, and Which Way Is Out
        # ------------------------------------------------------------
        # In plan, with a and b running from the anchor corner INTO the
        # rectangle. Past a corner it is the larger of the two overshoots, so
        # the eaves corner follows the cursor square rather than on a round.
        # Returns [reach, axis, direction]: outward is axis x direction.
        # ------------------------------------------------------------
        def na_roof__soffit_reach(point)
            u_axis, v_axis, _n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_key)
            sign_u = @na_sign_u.to_f < 0.0 ? -1.0 : 1.0
            sign_v = @na_sign_v.to_f < 0.0 ? -1.0 : 1.0

            offset = point - @na_point_a
            a      = offset.dot(u_axis).to_f * sign_u
            b      = offset.dot(v_axis).to_f * sign_v

            [
                [-a,                      u_axis, -sign_u],
                [a - @na_size_u.to_f.abs, u_axis,  sign_u],
                [-b,                      v_axis, -sign_v],
                [b - @na_size_v.to_f.abs, v_axis,  sign_v]
            ].max_by { |candidate| candidate[0] }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cut the Cursor Ray With the Plane the Soffit Is Read On
        # ------------------------------------------------------------
        def na_roof__soffit_plane_point(view, x, y)
            u_axis, v_axis, n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_key)
            looking = view.camera.direction
            steep   = looking.dot(n_axis).to_f

            top    = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(@na_point_a, n_axis, @na_roof_fascia)
            plane  =
                if steep.abs >= NA_ROOF_SOFFIT_GRAZING
                    [top, n_axis]
                else
                    facing = Geom::Vector3d.new(
                        looking.x - (n_axis.x * steep),
                        looking.y - (n_axis.y * steep),
                        looking.z - (n_axis.z * steep)
                    )
                    return nil unless facing.length > 0.0001

                    middle = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(top,    u_axis, na_drawn__signed_u * 0.5)
                    middle = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(middle, v_axis, na_drawn__signed_v * 0.5)
                    [middle, facing.normalize]
                end

            ray = view.pickray(x, y)
            hit = Geom.intersect_line_plane(ray, plane)
            na_drawn__point_in_front_of_ray?(ray, hit) ? hit : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Roof's Rise Is Measured From the Fascia Top
        # ------------------------------------------------------------
        # The cursor still rides the upright axis through the wall corner, as
        # for a roof alone; the fascia is taken off what it reads, and the roof
        # only ever rises off its plinth.
        # ------------------------------------------------------------
        def na_drawn__recalculate_sizes
            return super unless @na_state == :picking_depth && @na_roof_plinth_on == true
            return unless @na_point_a && @na_cursor_snapped
            return if na_drawn__locked?(:d)

            _u, _v, n_travel = Na__InsertPrimatives.Na__DrawnGrid__DecomposeToPlane(@na_point_a, @na_cursor_snapped, @na_plane_key)
            rise = n_travel.to_f - @na_roof_fascia.to_f

            @na_sign_d = 1.0
            @na_size_d = rise > 0.0 ? rise : 0.0
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Fascia or Soffit Stage
        # ------------------------------------------------------------
        # The wall line stays dashed underneath so the soffit reads as a
        # projection off it, and the plinth is drawn in the volume amber like
        # any other solid about to be added.
        # ------------------------------------------------------------
        def na_roof__draw_plinth_stage(view, wall_points)
            footprint = na_roof__footprint

            Na__InsertPrimatives.Na__DrawnPreview__DrawOutline(view, wall_points, NA_DRAWN_PLANE_BORDER_COLOR)
            Na__InsertPrimatives.Na__DrawnPreview__LabelRectangle(
                view, wall_points, @na_size_u, @na_size_v, na_drawn__locked?(:u), na_drawn__locked?(:v)
            )

            box = na_roof__draw_plinth_box(view, footprint)
            na_roof__draw_soffit_leader(view, wall_points) if @na_state == :picking_soffit

            anchor = box ? box[1][2] : wall_points[2]
            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor, na_roof__plinth_card_lines(footprint))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Plinth Box With Its Fascia Dimension
        # Returns [near, far], or nil while the fascia has no height.
        # ------------------------------------------------------------
        def na_roof__draw_plinth_box(view, footprint)
            return nil unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(footprint[:fascia])

            box = Na__InsertPrimatives.Na__DrawnRoof__PlinthBoxPoints(footprint, @na_plane_key)
            return nil unless box

            near, far = box
            Na__InsertPrimatives.Na__DrawnPreview__DrawFilledBox(
                view, near, far, NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
            )
            Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                view, near[1], far[1],
                "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:fascia]).abs} fascia",
                NA_DRAWN_TEXT_ACCENT_COLOR
            )
            box
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Leader From the Wall Face Out to the Eaves, Labelled
        # Drawn at the soffit's own level, off the middle of the first side.
        # ------------------------------------------------------------
        def na_roof__draw_soffit_leader(view, wall_points)
            return unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_roof_soffit)

            _u_axis, v_axis, _n_axis = Na__InsertPrimatives.Na__DrawnGrid__PlaneAxes(@na_plane_key)
            outward = @na_sign_v.to_f < 0.0 ? 1.0 : -1.0

            wall_mid = Geom::Point3d.new(
                (wall_points[0].x.to_f + wall_points[1].x.to_f) * 0.5,
                (wall_points[0].y.to_f + wall_points[1].y.to_f) * 0.5,
                (wall_points[0].z.to_f + wall_points[1].z.to_f) * 0.5
            )
            eaves_mid = Na__InsertPrimatives.Na__DrawnGrid__OffsetPoint(wall_mid, v_axis, outward * @na_roof_soffit)

            Na__InsertPrimatives.Na__DrawnPreview__DrawGuideLine(view, wall_mid, eaves_mid)
            Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                view, wall_mid, eaves_mid,
                "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_roof_soffit).abs} soffit",
                NA_DRAWN_TEXT_ACCENT_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Summary Card Lines for the Fascia and Soffit Stages
        # ------------------------------------------------------------
        def na_roof__plinth_card_lines(footprint)
            fascia_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:fascia]).abs
            soffit_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:soffit]).abs
            wall_u    = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_u).abs
            wall_v    = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_v).abs

            if @na_state == :picking_fascia
                return ["Fascia #{fascia_mm} mm", "Wall line #{wall_u} x #{wall_v} mm"]
            end

            [
                "Fascia #{fascia_mm}  ·  soffit #{soffit_mm} mm",
                "Eaves #{Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:u]).abs} x " \
                "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:v]).abs} mm"
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Summary Card for the Roof on Its Plinth
        # ------------------------------------------------------------
        def na_roof__summarise_plinth_roof(view, anchor_point, footprint)
            lines = [
                "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:u]).abs} x " \
                "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:v]).abs} eaves, " \
                "rise #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs} mm",
                "Pitch #{Na__InsertPrimatives.Na__DrawnFormat__Degrees(na_drawn__pitch_degrees)} deg  ·  #{na_drawn__volume_text} m3",
                "Fascia #{Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:fascia]).abs}  ·  " \
                "soffit #{Na__InsertPrimatives.Na__DrawnFormat__Mm(footprint[:soffit]).abs} mm"
            ]

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, anchor_point, lines)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Plinth Preview Occupies
        # ------------------------------------------------------------
        def na_roof__plinth_preview_points
            footprint = na_roof__footprint
            box       = Na__InsertPrimatives.Na__DrawnRoof__PlinthBoxPoints(footprint, @na_plane_key)
            return [] unless box

            points = box[0] + box[1]
            return points unless @na_state == :picking_depth

            points + Na__InsertPrimatives.Na__DrawnGrid__OffsetPointsAlongNormal(box[1], @na_plane_key, @na_size_d.to_f.abs)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Detail for the Fascia and Soffit Stages
        # ------------------------------------------------------------
        def na_roof__plinth_status
            fascia_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_roof_fascia).abs
            soffit_mm = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_roof_soffit).abs

            if @na_state == :picking_fascia
                return "Fascia #{fascia_mm} mm — pull up and click, or type its height (225, or 225,300 for the soffit too)"
            end

            "Soffit #{soffit_mm} mm on a #{fascia_mm} fascia — drag out past the wall and click, or type the projection (300)"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Value for the Plinth Stages
        # ------------------------------------------------------------
        def na_roof__plinth_vcb
            return ['Fascia height', na_drawn__format_sizes([@na_roof_fascia])] if @na_state == :picking_fascia

            ['Soffit projection', na_drawn__format_sizes([@na_roof_soffit])]
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Note for the Pitch Stage and the Revise Prompt
        # ------------------------------------------------------------
        def na_roof__plinth_note
            return '' unless na_roof__plinth_live?

            " on a #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_roof_fascia).abs} fascia, " \
            "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_roof_soffit).abs} soffit"
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | Does the Entry Name a Fascia or a Soffit?
        # ------------------------------------------------------------
        def na_roof__plinth_entry?(text)
            na_drawn__entry_parts(text).any? { |part| NA_ROOF_PLINTH_SUFFIX.match(part) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Split a Trailing f or s off a Part
        # Returns [slot or nil, the value text].
        # ------------------------------------------------------------
        def na_roof__split_suffix(part)
            match = NA_ROOF_PLINTH_SUFFIX.match(part.to_s.strip)
            return [nil, part.to_s.strip] unless match

            slot = match[2].downcase.start_with?('f') ? :fascia : :soffit
            [slot, match[1].to_s.strip]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Read an Entry Into Named Fascia, Soffit and Pitch Values
        # ------------------------------------------------------------
        # A lettered value goes where its letter says. The bare ones then fill
        # the slots still open, in order, from the stage being typed in: in
        # the fascia stage 225,300,35 is fascia, soffit, pitch, and so is
        # 300s,225,35. first_slot nil (revise) leaves no slot for a bare value.
        # Returns { slot => text } with the text still unparsed.
        # ------------------------------------------------------------
        def na_roof__read_plinth_entry(text, first_slot)
            order = first_slot ? NA_ROOF_PLINTH_SLOTS.drop(NA_ROOF_PLINTH_SLOTS.index(first_slot)) : []
            named = {}
            loose = []

            na_drawn__entry_parts(text).each do |part|
                slot, body = na_roof__split_suffix(part)

                if slot.nil?
                    loose << part
                    next
                end

                raise ArgumentError, "the #{slot} is typed twice" if named.key?(slot)
                raise ArgumentError, "'#{part}' has no size — e.g. 225f or 300s" if body.empty?
                named[slot] = body
            end

            free = order.reject { |slot| named.key?(slot) }
            raise ArgumentError, na_roof__too_many_message(first_slot) if loose.length > free.length

            loose.each_with_index { |part, index| named[free[index]] = part unless part.empty? }
            raise ArgumentError, 'no value entered' if named.empty?

            named
        end
        # ---------------------------------------------------------------

        # FUNCTION | What Each Stage Takes, for a Refusal That Names the Fix
        # ------------------------------------------------------------
        def na_roof__too_many_message(first_slot)
            case first_slot
            when :fascia then 'the fascia stage takes fascia, fascia,soffit or fascia,soffit,pitch — e.g. 225,300,35'
            when :soffit then 'the soffit stage takes soffit or soffit,pitch — e.g. 300,35'
            when :pitch  then 'a pitch takes a single value — 250f or 400s change the fascia and soffit'
            else              'type the fascia and soffit with their letters, e.g. 250f,400s — 35 on its own re-pitches the roof'
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve One Fascia or Soffit Value Against the Live One
        # ------------------------------------------------------------
        def na_roof__resolve_plinth_value(text, live_value)
            Na__InsertPrimatives.Na__DrawnVcb__ApplyToken(Na__InsertPrimatives.Na__DrawnVcb__ParseToken(text), live_value)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Refuse a Plinth That Cannot Be Built, Naming the Fix
        # ------------------------------------------------------------
        # Nothing is clamped. A fascia of nothing would leave a plinth with no
        # faces, and a soffit below nothing would set the eaves inside the
        # wall — so both are refused with what would work instead.
        # ------------------------------------------------------------
        def na_roof__validate_plinth(fascia, soffit, fascia_named)
            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(fascia)
                if fascia_named
                    raise ArgumentError, "a #{Na__InsertPrimatives.Na__DrawnFormat__Mm(fascia)}mm fascia is no fascia — give it a height such as 225, " \
                                         'or switch Fascia & Soffit off in the right-click menu for the roof alone'
                end

                raise ArgumentError, 'the fascia needs a height first — e.g. 225,300 for a 225 fascia and a 300 soffit'
            end

            return unless soffit.to_f < 0.0

            raise ArgumentError, "a #{Na__InsertPrimatives.Na__DrawnFormat__Mm(soffit)}mm soffit would set the eaves inside the wall — 0 keeps them flush with it"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply a Typed Fascia, Soffit or Pitch While Drawing
        # ------------------------------------------------------------
        # Moves on as far as the entry reaches: a fascia alone goes to the
        # soffit stage, a soffit to the pitch stage, and a pitch builds. A
        # value retyped in a later stage changes it and stays in that stage.
        # Everything is checked before anything is changed.
        # ------------------------------------------------------------
        def na_roof__apply_plinth_entry(text, view, first_slot)
            named  = na_roof__read_plinth_entry(text, first_slot)
            fascia = named[:fascia] ? na_roof__resolve_plinth_value(named[:fascia], @na_roof_fascia) : @na_roof_fascia.to_f
            soffit = named[:soffit] ? na_roof__resolve_plinth_value(named[:soffit], @na_roof_soffit) : @na_roof_soffit.to_f
            na_roof__validate_plinth(fascia, soffit, named.key?(:fascia))

            if named[:pitch]
                previous                        = [@na_roof_fascia, @na_roof_soffit]
                @na_roof_fascia, @na_roof_soffit = fascia, soffit             # <-- The pitch is measured over the eaves this entry sets

                begin
                    rise = na_drawn__resolve_rise_token(named[:pitch])
                    Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive([rise], ['Rise'])
                rescue ArgumentError
                    @na_roof_fascia, @na_roof_soffit = previous
                    raise
                end

                @na_size_d = rise
                @na_sign_d = 1.0
                return na_drawn__commit_roof(view)
            end

            @na_roof_fascia = fascia
            @na_roof_soffit = soffit

            if @na_state == :picking_fascia
                if named.key?(:soffit)
                    na_roof__begin_pitch_stage(view)
                else
                    @na_state = :picking_soffit
                    na_roof__mark_stage_entry
                end
            elsif @na_state == :picking_soffit && named.key?(:soffit)
                na_roof__begin_pitch_stage(view)
            end

            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Correct the Plinth of the Roof Just Built
        # ------------------------------------------------------------
        # The PITCH is held and the rise follows, because a roof is specified
        # by its pitch: a wider soffit makes a wider roof of the same pitch,
        # not a flatter one. Restored whole if the rebuild fails.
        # ------------------------------------------------------------
        def na_roof__revise_plinth(text, view)
            record = @na_last_record

            unless record && record[:plinth]
                raise ArgumentError, 'this roof was built without a fascia and soffit — switch Fascia & Soffit on in the right-click menu and draw it again'
            end

            named  = na_roof__read_plinth_entry(text, nil)
            fascia = named[:fascia] ? na_roof__resolve_plinth_value(named[:fascia], @na_roof_fascia) : @na_roof_fascia.to_f
            soffit = named[:soffit] ? na_roof__resolve_plinth_value(named[:soffit], @na_roof_soffit) : @na_roof_soffit.to_f
            na_roof__validate_plinth(fascia, soffit, named.key?(:fascia))

            pitch    = na_drawn__pitch_degrees
            previous = [@na_roof_fascia, @na_roof_soffit, @na_size_d, record[:plinth]]

            @na_roof_fascia = fascia
            @na_roof_soffit = soffit
            record[:plinth] = na_roof__plinth_spec
            @na_size_d      = Na__InsertPrimatives.Na__DrawnRoof__HeightFromPitch(pitch, na_drawn__pitch_run)

            return true if na_drawn__revise_roof(view)

            @na_roof_fascia, @na_roof_soffit, @na_size_d, record[:plinth] = previous
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnRoofFasciaSoffit module

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DRAWN ROOF FASCIA AND SOFFIT STAGES MODULE
# =============================================================================
