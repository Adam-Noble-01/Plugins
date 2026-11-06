# =============================================================================
# NA NOBLE DRAWING TOOLS - DRAWN ROOF FACE FOOTPRINT
# =============================================================================
#
# FILE       : Na__NobleDrawingTools__DrawnRoof__FaceFootprint__.rb
# NAMESPACE  : Na__NobleDrawingTools::DrawnRoofFaceFootprint
# AUTHOR     : Noble Architecture
# PURPOSE    : The Hipped Roof tool with a face selected: the face is the plan,
#              whatever its shape, and no rectangle is needed
# CREATED    : 2026
#
# DESCRIPTION:
# - Mixed into DrawnHippedRoofTool only, so it sits in front of DrawnRoofToolBase
#   and everything in it. Each override asks whether a face is in play and hands
#   straight back with super if not, so the rectangle tool is exactly as it was.
#   The Pitched Roof tool does not have it: a gable has to be told which ends are
#   gables, which a plan alone does not say.
#
# THE GESTURE, END TO END:
#   Select a face, then start the tool. The rectangle stage is skipped:
#   1  pull up the fascia and click, or type 225            (:picking_fascia)
#   2  drag out the soffit and click, or type 300           (:picking_soffit)
#   3  pull up the roof or type a pitch                     (:picking_depth)
#   With Fascia & Soffit off it starts at 3. Everything typed means what it means
#   on a rectangle, 225,300,35 included. Afterwards 35 re-pitches, 250f and 400s
#   correct the plinth. A plan size is refused: the face is the plan.
#
# THE ANCHOR FOLLOWS THE CURSOR:
# - The drag reads height up a line through @na_point_a. For a rectangle that is
#   the corner just clicked, under the cursor. Here nothing has been clicked, so
#   the anchor is put under the cursor at each stage's first mouse move, and the
#   reading starts from nothing wherever the cursor happens to be. Well off the
#   plan it is held back, or a cursor near the horizon would measure up a line
#   a mile away.
#
# NO RIDGE DIRECTION TO CHOOSE:
# - One pitch and one plan leave nothing to decide, so TAB and the arrows say so
#   and change nothing.
#
# THE SELECTION IS SET ASIDE:
# - BKSP and DEL both step back in these tools, and SketchUp's own Delete shortcut
#   gets the key first and deletes the selection: the face, in this case. So the
#   selection is emptied while the tool holds a face, and put back when the tool
#   ends. The preview draws the plan in its place. See Deep Scale's Keys file.
#
# COORDINATES:
# - World throughout: the selected face is in the open context, so it reads world,
#   as do the pick rays and the preview. No edit_transform anywhere. See
#   DrawnRoofFootprint.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__NobleDrawingTools__DrawnToolShared__'
require_relative '../04__GeometryHelpers/Na__NobleDrawingTools__DrawnRoofFootprint__'

module Na__NobleDrawingTools

    # =============================================================================
    # MODULE | The Hipped Roof Over a Selected Face
    # =============================================================================

    module DrawnRoofFaceFootprint

        # -----------------------------------------------------------------------------
        # REGION | Life Cycle
        # -----------------------------------------------------------------------------

        # ACTIVATE | A Face in the Selection Goes Straight to Its First Stage
        # ------------------------------------------------------------
        def activate
            super
            na_roof__take_selected_face
        end
        # ---------------------------------------------------------------

        # DEACTIVATE | Put the Selection Back
        # ------------------------------------------------------------
        def deactivate(view)
            na_roof__give_selection_back
            super
        end
        # ---------------------------------------------------------------

        # ON MOUSE MOVE | Watch the Selection, Then Place the Anchor
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_roof__watch_selection
            na_roof__settle_face_anchor(view, x, y)
            super
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | A Click With No Move Before It Still Has an Anchor
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            na_roof__settle_face_anchor(view, x, y)
            super
        end
        # ---------------------------------------------------------------

        # ON KEY DOWN | Anything Selected Meanwhile Is Set Aside Before DEL Can Reach It
        # ------------------------------------------------------------
        def onKeyDown(key, repeat, flags, view)
            na_roof__watch_selection
            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'SELECT A FACE FIRST and it is the plan, any shape: hips, valleys and ridges are worked out from it'
            ] + super
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Taking the Face
        # -----------------------------------------------------------------------------

        # FUNCTION | Use the Selected Face as the Plan, If There Is One
        # ------------------------------------------------------------
        # Returns true if a face was taken. A face no roof can be worked out for is
        # said out loud and left alone, and the rectangle is still there to drag.
        # ------------------------------------------------------------
        def na_roof__take_selected_face
            model = Sketchup.active_model
            return false unless model

            faces = model.selection.grep(Sketchup::Face).select { |face| face.valid? }
            return false if faces.empty?

            face      = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ChooseFace(faces)
            footprint = Na__NobleDrawingTools.Na__DrawnRoofFootprint__FromFace(face)

            unless footprint && Na__NobleDrawingTools.Na__DrawnRoofFootprint__Solution(footprint, 0.0)
                UI.beep
                Sketchup::set_status_text('No roof can be worked out for that face — drag a rectangle instead', SB_PROMPT)
                na_roof__hold_selection(model)
                return false
            end

            footprint[:note] = "largest of #{faces.length} selected faces" if faces.length > 1

            na_roof__hold_selection(model)
            na_roof__begin_face_stages(footprint)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Start the Stages Over a Footprint
        # ------------------------------------------------------------
        def na_roof__begin_face_stages(footprint)
            na_drawn__clear_locks
            na_drawn__disarm_revise

            @na_roof_face           = footprint
            @na_plane_key           = :xy
            @na_axis_lock           = nil
            @na_ip_origin           = Sketchup::InputPoint.new                # <-- Inference from a corner of an older drag would mislead
            @na_drag_press_active   = false
            @na_size_u              = 0.0
            @na_size_v              = 0.0
            @na_size_d              = 0.0
            @na_sign_u              = 1.0
            @na_sign_v              = 1.0
            @na_sign_d              = 1.0
            @na_roof_fascia         = 0.0
            @na_roof_soffit         = 0.0
            @na_roof_plinth_on      = na_roof__plinth_option? ? true : false
            @na_point_a             = footprint[:origin]                      # <-- Until the mouse moves and says where it is
            @na_state               = @na_roof_plinth_on ? :picking_fascia : :picking_depth

            na_roof__mark_stage_entry
            na_drawn__update_status_text
            na_drawn__refresh_vcb

            model = Sketchup.active_model
            model.active_view.invalidate if model && model.active_view
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Footprint in Play: Being Drawn, or Just Built and On Offer
        # ------------------------------------------------------------
        def na_roof__face_source
            return @na_roof_face if @na_roof_face
            return nil unless @na_state == :idle

            @na_last_record ? @na_last_record[:footprint] : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Live Soffit, as the Plan's Eaves Take It
        # ------------------------------------------------------------
        def na_roof__face_soffit
            na_roof__plinth_live? ? @na_roof_soffit.to_f.abs : 0.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Roof Over the Live Eaves, or nil
        # ------------------------------------------------------------
        def na_roof__face_solution(footprint = na_roof__face_source)
            return nil unless footprint

            Na__NobleDrawingTools.Na__DrawnRoofFootprint__Solution(footprint, na_roof__face_soffit)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Dropped Drag Drops the Face With It
        # ------------------------------------------------------------
        # So after ESC or a build the next drag is a rectangle. The selection stays
        # aside: put back now, the next mouse move would take the same face again,
        # and ESC could never let go of it.
        # ------------------------------------------------------------
        def na_drawn__on_pick_state_reset
            super
            @na_roof_face           = nil
            @na_roof_anchor_pending = false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | The Selection, Set Aside While the Tool Holds a Face
        # -----------------------------------------------------------------------------

        # FUNCTION | Empty SketchUp's Selection, Keeping What Was in It for Later
        # ------------------------------------------------------------
        def na_roof__hold_selection(model)
            @na_roof_aside = { :entities => model.selection.to_a, :context => model.active_path }
            model.selection.clear
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Answer Anything Selected While the Tool Runs
        # ------------------------------------------------------------
        # Other things can select while a tool runs: the Outliner, Select All. Idle,
        # a face arriving is taken up as if the tool had started with it. Holding a
        # face, whatever arrives goes aside before DEL can get at it. With neither,
        # the selection is left alone, as the rectangle tool always has.
        # ------------------------------------------------------------
        def na_roof__watch_selection
            model = Sketchup.active_model
            return unless model && model.selection.length > 0

            if @na_roof_face
                na_roof__hold_selection(model)
            elsif @na_state == :idle
                na_roof__take_selected_face
            end
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Tool Is Ending: Put the Selection Back
        # ------------------------------------------------------------
        # Only what still exists. Not after a change of open group, which empties
        # the selection in SketchUp too: entities can only be selected from the
        # context they sit in.
        # ------------------------------------------------------------
        def na_roof__give_selection_back
            aside          = @na_roof_aside
            @na_roof_aside = nil
            model          = Sketchup.active_model
            return false unless model && aside
            return false unless Na__NobleDrawingTools.Na__DeepPick__SameContext?(model.active_path, aside[:context])

            live = aside[:entities].select { |entity| entity.valid? }
            return false if live.empty?

            model.selection.add(live)
            true
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Anchor and Cursor
        # -----------------------------------------------------------------------------

        # FUNCTION | A New Stage Wants the Anchor Under the Cursor Again
        # ------------------------------------------------------------
        def na_roof__mark_stage_entry
            super
            @na_roof_anchor_pending = true if @na_roof_face
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put the Anchor Under the Cursor
        # ------------------------------------------------------------
        # On the level the stage reads from, then down on to the plan's own plane:
        # the fascia reads up from the plan, the soffit and the roof from the fascia
        # top. So each stage opens reading nothing, wherever the cursor is.
        # ------------------------------------------------------------
        def na_roof__settle_face_anchor(view, x, y)
            return unless @na_roof_face && @na_roof_anchor_pending

            @na_roof_anchor_pending = false

            footprint = @na_roof_face
            up        = footprint[:n]
            level     = @na_state == :picking_fascia ? 0.0 : @na_roof_fascia.to_f.abs
            ray       = view.pickray(x, y)
            on_level  = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, 0.0, 0.0, level)
            hit       = Geom.intersect_line_plane(ray, [on_level, up])
            return unless na_drawn__point_in_front_of_ray?(ray, hit)

            low, high = Na__NobleDrawingTools.Na__DrawnRoofFootprint__PlanBox(footprint)
            reach     = (high[0] - low[0]) + (high[1] - low[1])
            plan_x, plan_y = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToPlan(footprint, hit)

            plan_x = [[plan_x, low[0] - reach].max, high[0] + reach].min      # <-- Off towards the horizon is not where a roof is
            plan_y = [[plan_y, low[1] - reach].max, high[1] + reach].min

            @na_point_a = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, plan_x, plan_y, 0.0)
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Way the Roof Rises: Square to the Face
        # ------------------------------------------------------------
        def na_roof__up_axis
            return super unless @na_roof_face

            @na_roof_face[:n]
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Middle of the Plan at a Given Level
        # ------------------------------------------------------------
        def na_roof__wall_middle(top)
            return super unless @na_roof_face

            footprint = @na_roof_face
            x, y      = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Middle(footprint)
            level     = (top - footprint[:origin]).dot(footprint[:n]).to_f

            Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, x, y, level)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Project the Pick Ray on to the Line Up Through the Anchor
        # ------------------------------------------------------------
        def na_drawn__depth_point_from_ray(view, x, y)
            return super unless @na_roof_face

            ray     = view.pickray(x, y)
            closest = Geom.closest_points([@na_point_a, @na_roof_face[:n]], ray)
            return nil unless closest && closest[0]

            na_drawn__point_in_front_of_ray?(ray, closest[0]) ? closest[0] : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Far Past the Wall Line the Cursor Is
        # ------------------------------------------------------------
        def na_roof__soffit_reach(point)
            return super unless @na_roof_face

            Na__NobleDrawingTools.Na__DrawnRoofFootprint__OutsideReach(@na_roof_face, point)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Roof's Rise Is Measured From the Fascia Top
        # ------------------------------------------------------------
        # Rounded as a distance, not as a point: a face seldom sits on a whole grid
        # step, and the roof above it should still rise by a whole number of them.
        # ------------------------------------------------------------
        def na_drawn__recalculate_sizes
            return super unless @na_roof_face
            return unless @na_state == :picking_depth && @na_point_a && @na_cursor_raw
            return if na_drawn__locked?(:d)

            up     = @na_roof_face[:n]
            travel = (@na_cursor_raw - @na_point_a).dot(up).to_f
            base   = @na_roof_plinth_on == true ? @na_roof_fascia.to_f.abs : 0.0
            rise   = na_drawn__snap_distance(travel - base).to_f

            @na_cursor_snapped = Na__NobleDrawingTools.Na__DrawnGrid__OffsetPoint(@na_cursor_raw, up, rise - (travel - base))
            @na_sign_d         = 1.0
            @na_size_d         = rise > 0.0 ? rise : 0.0
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Keys With Nothing to Decide
        # -----------------------------------------------------------------------------

        # FUNCTION | TAB Has No Ridge Direction to Change Over a Face
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            return super unless @na_roof_face

            Sketchup::set_status_text('The ridges follow the face — there is no direction to choose', SB_PROMPT)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nor Have the Arrow Keys
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            return super unless @na_roof_face

            Sketchup::set_status_text('The ridges follow the face — there is no direction to choose', SB_PROMPT)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What the Keys Do Over a Face
        # ------------------------------------------------------------
        def na_drawn__key_hints
            return super unless @na_roof_face

            "#{na_drawn__vertex_hint}  BKSP back  ESC cancel"
        end
        # ---------------------------------------------------------------

        # FUNCTION | BKSP Past the First Stage Lets Go of the Face
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            return super unless @na_roof_face
            return super unless @na_state == (@na_roof_plinth_on == true ? :picking_fascia : :picking_depth)

            na_drawn__reset_pick_state
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Metrics
        # -----------------------------------------------------------------------------

        # FUNCTION | The Horizontal Run the Pitch Is Read Over
        # ------------------------------------------------------------
        # How far an eaves walks before the last of the plan closes: on a rectangle
        # that is half the span, and the rise is the height of the top of the roof.
        # ------------------------------------------------------------
        def na_drawn__pitch_run
            footprint = na_roof__face_source
            return super unless footprint

            solution = na_roof__face_solution(footprint)
            solution ? solution[:height].to_f : 0.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | There Is No Single Ridge to Collapse
        # ------------------------------------------------------------
        def na_drawn__pyramid?
            na_roof__face_source ? false : super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Live Roof Mass Volume as a Formatted String
        # ------------------------------------------------------------
        def na_drawn__volume_text
            footprint = na_roof__face_source
            return super unless footprint

            solution = na_roof__face_solution(footprint)
            return format('%.3f', 0.0) unless solution

            Na__NobleDrawingTools.Na__DrawnRoofFootprint__VolumeM3(solution, @na_size_d)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Fragment Where the Rectangle Would Name Its Ridge
        # ------------------------------------------------------------
        def na_drawn__plane_description
            footprint = @na_roof_face
            return super unless footprint

            note = footprint[:note] ? " (#{footprint[:note]})" : ''
            yard = footprint[:courtyards].to_i > 0 ? ", #{footprint[:courtyards]} courtyard#{footprint[:courtyards] == 1 ? '' : 's'}" : ''
            "On the selected face#{note}: #{footprint[:sides]} sides#{yard}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            if @na_state == :idle && !na_drawn__revise_available?
                return 'Click and drag out the wall line the roof sits on, or select a face first and it is the plan' if na_roof__plinth_option?

                return 'Click and drag out the plan footprint, or select a face first and it is the plan'
            end

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        # A roof over a face has no width and length to offer back.
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Roof pitch', na_drawn__pitch_vcb_text] if @na_state == :idle && na_drawn__revise_available? && na_roof__face_source

            super
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Typed Plan Size Means Nothing Over a Face: the Face Is the Plan
        # ------------------------------------------------------------
        def na_drawn__apply_typed_sizes(text)
            return super unless na_roof__face_source

            raise ArgumentError, 'the face is the plan, so it has no size to type — type a pitch (35), a rise (3000mm), or 250f / 400s'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Commit and Revise
        # -----------------------------------------------------------------------------

        # FUNCTION | Build the Roof Over the Face
        # ------------------------------------------------------------
        def na_drawn__commit_roof(view)
            footprint = @na_roof_face
            return super unless footprint

            unless Na__NobleDrawingTools.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                Sketchup::set_status_text('Roof has no rise — pull up or type a pitch', SB_PROMPT)
                return false
            end

            plinth = @na_roof_plinth_on == true ? na_roof__plinth_spec : nil

            unless Na__NobleDrawingTools.Na__DrawnRoof__PlinthBuildable?(plinth)
                UI.beep
                Sketchup::set_status_text('The fascia has no height — pull it up, or type one such as 225', SB_PROMPT)
                return false
            end

            rise   = @na_size_d.to_f.abs
            pitch  = na_drawn__pitch_degrees
            volume = na_drawn__volume_text
            group  = Na__NobleDrawingTools.Na__DrawnRoofFootprint__CreateRoof(footprint, rise, plinth)

            unless group
                UI.beep
                Sketchup::set_status_text('Could not build a roof over that face', SB_PROMPT)
                return false
            end

            @na_last_record = {
                :group      => group,
                :origin     => footprint[:origin],
                :plane_key  => :xy,
                :sign_u     => 1.0,
                :sign_v     => 1.0,
                :sign_d     => 1.0,
                :ridge_axis => :auto,
                :plinth     => plinth,
                :footprint  => footprint
            }

            Na__NobleDrawingTools.Na__DrawnRoof__RememberPlinth(plinth)
            na_drawn__reset_pick_state
            na_drawn__arm_revise
            na_roof__log_face_roof('CREATED', group, footprint, rise, pitch, volume, plinth)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild the Last Roof Over Its Face
        # ------------------------------------------------------------
        def na_drawn__revise_roof(view)
            record = @na_last_record
            return super unless record && record[:footprint]

            rise    = @na_size_d.to_f.abs
            rebuilt = Na__NobleDrawingTools.Na__DrawnRoofFootprint__RebuildRoof(record[:group], record[:footprint], rise, record[:plinth])

            unless rebuilt
                UI.beep
                Sketchup::set_status_text('Could not rebuild that roof', SB_PROMPT)
                return false
            end

            Na__NobleDrawingTools.Na__DrawnRoof__RememberPlinth(record[:plinth])
            na_drawn__arm_revise
            na_roof__log_face_roof('ADJUSTED', record[:group], record[:footprint], rise, na_drawn__pitch_degrees, na_drawn__volume_text, record[:plinth])
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Roof Over a Face
        # ------------------------------------------------------------
        def na_roof__log_face_roof(action, group, footprint, rise, pitch, volume, plinth)
            soffit   = plinth ? plinth[:soffit].to_f.abs : 0.0
            eaves    = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Eaves(footprint, soffit)
            solution = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Solution(footprint, soffit)

            Na__NobleDrawingTools.Na__Debug__Puts "\n"
            Na__NobleDrawingTools.Na__Debug__Puts '----------------------------------------'
            Na__NobleDrawingTools.Na__Debug__Puts "#{na_drawn__roof_label.upcase} #{action} OVER A FACE"
            Na__NobleDrawingTools.Na__Debug__Puts "Plan  : #{footprint[:sides]} sides, #{format('%.2f', footprint[:area].to_f.abs * (NA_DRAWN_INCH_TO_MM**2) / 1_000_000.0)} m2"

            if plinth && eaves
                Na__NobleDrawingTools.Na__Debug__Puts "Eaves : #{eaves[:sides]} sides, #{format('%.2f', eaves[:area].to_f.abs * (NA_DRAWN_INCH_TO_MM**2) / 1_000_000.0)} m2"
                Na__NobleDrawingTools.Na__Debug__Puts "Fascia: #{Na__NobleDrawingTools.Na__DrawnFormat__Mm(plinth[:fascia]).abs}mm  Soffit: #{Na__NobleDrawingTools.Na__DrawnFormat__Mm(plinth[:soffit]).abs}mm  (#{Na__NobleDrawingTools.Na__DrawnRoofFootprint__PlinthVolumeM3(eaves, plinth[:fascia])} m3)"
            end

            Na__NobleDrawingTools.Na__Debug__Puts "Rise  : #{Na__NobleDrawingTools.Na__DrawnFormat__Mm(rise).abs}mm"
            Na__NobleDrawingTools.Na__Debug__Puts "Pitch : #{Na__NobleDrawingTools.Na__DrawnFormat__Degrees(pitch)} deg"
            Na__NobleDrawingTools.Na__Debug__Puts "Lines : #{Na__NobleDrawingTools.Na__DrawnRoofFootprint__LineWords(solution)}" if solution
            Na__NobleDrawingTools.Na__Debug__Puts "Volume: #{volume} m3"
            Na__NobleDrawingTools.Na__Debug__Puts "Solid : #{Na__NobleDrawingTools.Na__DrawnRoof__SolidState(group)}"
            Na__NobleDrawingTools.Na__Debug__Puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Draw the Plan, the Plinth and the Roof Over the Face
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            footprint = @na_roof_face
            return super unless footprint

            plinth = @na_roof_plinth_on == true
            soffit = plinth ? @na_roof_soffit.to_f.abs : 0.0
            fascia = plinth ? @na_roof_fascia.to_f.abs : 0.0
            eaves  = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Eaves(footprint, soffit)

            Na__NobleDrawingTools.Na__DrawnRoofFootprint__LoopsInWorld(footprint, footprint[:loops], 0.0).each do |wall_line|
                Na__NobleDrawingTools.Na__DrawnPreview__DrawOutline(view, wall_line, NA_DRAWN_PLANE_BORDER_COLOR)
            end

            solution = @na_state == :picking_depth ? Na__NobleDrawingTools.Na__DrawnRoofFootprint__Solution(footprint, soffit) : nil
            has_rise = solution && Na__NobleDrawingTools.Na__DrawnGeom__ValidDimension?(@na_size_d)
            has_box  = plinth && eaves && Na__NobleDrawingTools.Na__DrawnGeom__ValidDimension?(fascia)

            na_roof__fill_face_plan(view, footprint) unless has_box || has_rise
            na_roof__draw_face_plinth(view, footprint, eaves, fascia) if has_box
            na_roof__draw_face_soffit_leader(view, footprint, soffit) if @na_state == :picking_soffit
            na_roof__draw_face_roof(view, footprint, solution, fascia) if has_rise

            na_roof__draw_face_card(view, footprint, eaves, solution, fascia, soffit)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Shade the Plan, While There Is Nothing Yet Standing on It
        # ------------------------------------------------------------
        # The selection is set aside, so this is what says which face is in use.
        # ------------------------------------------------------------
        def na_roof__fill_face_plan(view, footprint)
            eaves = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Eaves(footprint, 0.0)
            return unless eaves

            eaves[:groups].each do |group|
                world = Na__NobleDrawingTools.Na__DrawnRoofFootprint__GroupInWorld(footprint, group, 0.0)
                Na__NobleDrawingTools.Na__DrawnPreview__DrawTriangles(view, world[:triangles], NA_DRAWN_PLANE_FILL_COLOR)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Plinth With Its Fascia Dimension
        # ------------------------------------------------------------
        def na_roof__draw_face_plinth(view, footprint, eaves, fascia)
            near_loops = Na__NobleDrawingTools.Na__DrawnRoofFootprint__LoopsInWorld(footprint, eaves[:loops], 0.0)
            far_loops  = Na__NobleDrawingTools.Na__DrawnRoofFootprint__LoopsInWorld(footprint, eaves[:loops], fascia)
            triangles  = eaves[:groups].flat_map do |group|
                Na__NobleDrawingTools.Na__DrawnRoofFootprint__GroupInWorld(footprint, group, fascia)[:triangles]
            end

            Na__NobleDrawingTools.Na__DrawnPreview__DrawFilledPrism(
                view, near_loops, far_loops, triangles, NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR
            )
            Na__NobleDrawingTools.Na__DrawnPreview__DrawEdgeLabel(
                view, near_loops[0][0], far_loops[0][0],
                "#{Na__NobleDrawingTools.Na__DrawnFormat__Mm(fascia).abs} fascia",
                NA_DRAWN_TEXT_ACCENT_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Leader From the Longest Wall Out to the Eaves, Labelled
        # ------------------------------------------------------------
        def na_roof__draw_face_soffit_leader(view, footprint, soffit)
            return unless Na__NobleDrawingTools.Na__DrawnGeom__ValidDimension?(soffit)

            wall = Na__NobleDrawingTools.Na__DrawnRoofFootprint__LongestWall(footprint)
            return unless wall

            wall_mid  = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, wall[0], wall[1], 0.0)
            eaves_mid = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, wall[0] + (wall[2] * soffit), wall[1] + (wall[3] * soffit), 0.0)

            Na__NobleDrawingTools.Na__DrawnPreview__DrawGuideLine(view, wall_mid, eaves_mid)
            Na__NobleDrawingTools.Na__DrawnPreview__DrawEdgeLabel(
                view, wall_mid, eaves_mid,
                "#{Na__NobleDrawingTools.Na__DrawnFormat__Mm(soffit).abs} soffit",
                NA_DRAWN_TEXT_ACCENT_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Draw the Slopes, Heavy Ridges, and the Pitch on the Top One
        # ------------------------------------------------------------
        def na_roof__draw_face_roof(view, footprint, solution, fascia)
            world = Na__NobleDrawingTools.Na__DrawnRoofFootprint__RoofInWorld(footprint, solution, fascia, @na_size_d)

            Na__NobleDrawingTools.Na__DrawnPreview__DrawFilledLoops(view, world[:faces], NA_DRAWN_VOLUME_FILL_COLOR, NA_DRAWN_VOLUME_BORDER_COLOR)

            ridges = world[:lines].select { |line| line[:kind] == :ridge }
            ridges.each { |line| Na__NobleDrawingTools.Na__DrawnPreview__DrawRidgeLine(view, line[:a], line[:b]) }

            top = ridges.max_by { |line| [line[:top].round(3), line[:a].distance(line[:b]).to_f] }
            return unless top

            Na__NobleDrawingTools.Na__DrawnPreview__DrawEdgeLabel(
                view, top[:a], top[:b],
                "#{Na__NobleDrawingTools.Na__DrawnFormat__Degrees(na_drawn__pitch_degrees)} deg",
                NA_DRAWN_TEXT_ACCENT_COLOR
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Summary Card Beside the Plan
        # ------------------------------------------------------------
        def na_roof__draw_face_card(view, footprint, eaves, solution, fascia, soffit)
            source = eaves ? eaves[:loops].first : footprint[:loops].first
            corner = source.max_by { |point| point[0] + point[1] }
            anchor = Na__NobleDrawingTools.Na__DrawnRoofFootprint__ToWorld(footprint, corner[0], corner[1], fascia)

            Na__NobleDrawingTools.Na__DrawnPreview__DrawWorldLabel(
                view, anchor, na_roof__face_card_lines(footprint, eaves, solution, fascia, soffit)
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Summary Card Lines for the Stage in Hand
        # ------------------------------------------------------------
        def na_roof__face_card_lines(footprint, eaves, solution, fascia, soffit)
            fascia_mm = Na__NobleDrawingTools.Na__DrawnFormat__Mm(fascia).abs
            soffit_mm = Na__NobleDrawingTools.Na__DrawnFormat__Mm(soffit).abs

            case @na_state
            when :picking_fascia
                ["Fascia #{fascia_mm} mm", "Over the selected face: #{footprint[:sides]} sides"]
            when :picking_soffit
                ["Fascia #{fascia_mm}  ·  soffit #{soffit_mm} mm", "Eaves: #{eaves ? eaves[:sides] : 0} sides"]
            else
                lines = ["Rise #{Na__NobleDrawingTools.Na__DrawnFormat__Mm(@na_size_d).abs} mm  ·  pitch #{Na__NobleDrawingTools.Na__DrawnFormat__Degrees(na_drawn__pitch_degrees)} deg  ·  #{na_drawn__volume_text} m3"]
                lines << "Fascia #{fascia_mm}  ·  soffit #{soffit_mm} mm" if @na_roof_plinth_on == true
                lines << (solution ? Na__NobleDrawingTools.Na__DrawnRoofFootprint__LineWords(solution) : 'No roof can be worked out for these eaves')
                lines
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Point the Preview Occupies
        # ------------------------------------------------------------
        def na_drawn__preview_points
            footprint = @na_roof_face
            return super unless footprint

            plinth = @na_roof_plinth_on == true
            soffit = plinth ? @na_roof_soffit.to_f.abs : 0.0
            fascia = plinth ? @na_roof_fascia.to_f.abs : 0.0
            eaves  = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Eaves(footprint, soffit)
            source = eaves ? eaves[:loops] : footprint[:loops]
            points = Na__NobleDrawingTools.Na__DrawnRoofFootprint__LoopsInWorld(footprint, source, 0.0).flatten(1)

            points += Na__NobleDrawingTools.Na__DrawnRoofFootprint__LoopsInWorld(footprint, source, fascia).flatten(1)
            return points unless @na_state == :picking_depth

            solution = Na__NobleDrawingTools.Na__DrawnRoofFootprint__Solution(footprint, soffit)
            return points unless solution

            world = Na__NobleDrawingTools.Na__DrawnRoofFootprint__RoofInWorld(footprint, solution, fascia, @na_size_d)
            points + world[:faces].flat_map { |face| face[:outer] }
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnRoofFaceFootprint module

end # End Na__NobleDrawingTools module

# =============================================================================
# END OF DRAWN ROOF FACE FOOTPRINT MODULE
# =============================================================================
