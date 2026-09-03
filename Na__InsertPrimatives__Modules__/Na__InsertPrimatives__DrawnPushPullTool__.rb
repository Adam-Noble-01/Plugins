# =============================================================================
# NA INSERT PRIMATIVES - DEEP PUSH PULL TOOL
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPullTool__.rb
# NAMESPACE  : Na__InsertPrimatives
# CLASS      : DrawnPushPullTool
# AUTHOR     : Noble Architecture
# PURPOSE    : Push/pull any face at any nesting depth, on the shared voxel grid
# CREATED    : 2026
#
# DESCRIPTION:
# - Hover to highlight the face under the cursor, click to grab it, drag to push,
#   click again to place. One click fewer than native when the face is buried:
#   there is no double-clicking down through groups first.
# - Distances snap to the shared voxel step, CTRL suspends that for vertex
#   snapping, and the measurements box pins the distance — the same three
#   controls every other tool in this plugin uses.
#
# WHY THE DISTANCE IS SNAPPED, NOT THE POINT:
# - Elsewhere the cursor point is rounded onto the lattice. That is wrong here:
#   a face normal is rarely axis-aligned, so rounding a point on it would give
#   ragged distances. The travel along the push direction is snapped instead,
#   which keeps clean 5mm pushes whatever angle the face sits at.
#
# ARROW KEY AXIS LOCK — WHAT IT ACTUALLY MEANS:
# - Sketchup::Face#pushpull only ever extrudes along the face normal, so a lock
#   cannot redirect the extrusion. What it does instead is change what the drag
#   MEASURES: lock to Z and drag 1000, and the face is pushed far enough along
#   its own normal to end up 1000 higher. Pushing a sloped roof plane up by a
#   known vertical is a real gap in the native tool, and this closes it.
# - A face whose normal is near-perpendicular to the locked axis cannot move
#   along that axis at all, so the lock is refused rather than dividing by
#   something close to zero.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__InsertPrimatives__DrawnToolShared__'
require_relative 'Na__InsertPrimatives__DrawnDeepPick__'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Deep Push Pull Tool Class
    # -----------------------------------------------------------------------------

    # CLASS | Push/Pull Any Face at Any Nesting Depth
    # ------------------------------------------------------------
    class DrawnPushPullTool

        include Na__InsertPrimatives::DrawnToolShared

        NA_PP_MIN_AXIS_FACTOR = 0.0872                                        # <-- cos 85 degrees; below this the lock is refused
        NA_PP_HOVER_FILL      = Sketchup::Color.new(  0, 140, 255,  80)
        NA_PP_HOVER_BORDER    = Sketchup::Color.new(  0, 110, 235, 235)
        NA_PP_RESULT_FILL     = Sketchup::Color.new(255, 150,  30,  70)
        NA_PP_RESULT_BORDER   = Sketchup::Color.new(226, 118,   0, 235)

        # INITIALIZE | Tool Constructor
        # ------------------------------------------------------------
        def initialize
            na_drawn__init_shared_state
            na_drawn__clear_target
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Trace of Every Decision Point
        # Off by default. Turn it on from the Ruby Console with
        #   Na__InsertPrimatives.Na__PushPull__SetTrace(true)
        # and every grab, placement and refusal prints with the state it saw.
        # Diagnosing this tool from screenshots cost three wrong guesses; this
        # exists so the next question is answered with a log instead.
        # ------------------------------------------------------------
        def na_drawn__trace(message)
            return unless Na__InsertPrimatives.Na__PushPull__Trace?

            puts "[NA PUSHPULL] #{message} | state=#{@na_state.inspect} " \
                 "dist=#{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm " \
                 "face=#{@na_pp_target && @na_pp_target[:face] ? @na_pp_target[:face].entityID : 'none'} " \
                 "ctrl=#{@na_ctrl_held ? 'on' : 'off'} axis=#{@na_axis_lock.inspect}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Forget the Currently Grabbed Face
        # ------------------------------------------------------------
        def na_drawn__clear_target
            @na_pp_target      = nil
            @na_pp_triangles   = []
            @na_pp_loop        = []
            @na_pp_area        = '0.00'
            @na_pp_fingerprint = nil
        end
        # ---------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Identity
        # -----------------------------------------------------------------------------

        # FUNCTION | Status Bar Title
        # ------------------------------------------------------------
        def na_drawn__tool_title
            'Deep Push/Pull'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Popup Menu Highlight Key
        # ------------------------------------------------------------
        def na_drawn__mode_key
            :drawn_push_pull
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Banner Hint Lines
        # ------------------------------------------------------------
        def na_drawn__activation_hints
            [
                'Hover any face, click to grab it, drag to push, click to place',
                'Reaches faces inside groups and components without opening them',
                "Distance snaps to the #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel} grid — hold CTRL for vertex snapping",
                'ARROWS lock the measured axis: Right X, Left Y, Up Z, Down releases',
                'VCB: 300 | +50 | -25   (the typed distance pins and places)'
            ]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Push Direction and Distance Maths
        # -----------------------------------------------------------------------------

        # FUNCTION | World Unit Normal of the Grabbed Face
        # ------------------------------------------------------------
        def na_drawn__face_normal
            return nil unless @na_pp_target

            @na_pp_target[:world_normal]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Direction the Drag Is Measured Along
        # ------------------------------------------------------------
        def na_drawn__push_direction
            locked = @na_axis_lock ? Na__InsertPrimatives.Na__DrawnGrid__AxisVector(@na_axis_lock) : nil
            locked || na_drawn__face_normal
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Much of the Locked Axis the Face Normal Carries
        # This is the cosine between the two, and the divisor that converts a
        # distance along the axis into a distance along the normal.
        # ------------------------------------------------------------
        def na_drawn__axis_normal_factor
            normal = na_drawn__face_normal
            axis   = @na_axis_lock ? Na__InsertPrimatives.Na__DrawnGrid__AxisVector(@na_axis_lock) : nil
            return 1.0 unless normal && axis

            axis.dot(normal).to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | Can the Face Move Along the Locked Axis at All?
        # ------------------------------------------------------------
        def na_drawn__axis_lock_usable?
            return true unless @na_axis_lock

            na_drawn__axis_normal_factor.abs >= NA_PP_MIN_AXIS_FACTOR
        end
        # ---------------------------------------------------------------

        # FUNCTION | Signed World Distance the Face Travels Along Its Normal
        # ------------------------------------------------------------
        def na_drawn__world_normal_travel
            travel = na_drawn__signed_d
            return travel unless @na_axis_lock

            factor = na_drawn__axis_normal_factor
            return 0.0 if factor.abs < NA_PP_MIN_AXIS_FACTOR

            travel / factor
        end
        # ---------------------------------------------------------------

        # FUNCTION | World Offset Vector Applied to the Preview Face
        # ------------------------------------------------------------
        def na_drawn__push_offset_vector
            normal = na_drawn__face_normal
            return nil unless normal

            distance = na_drawn__world_normal_travel
            Geom::Vector3d.new(
                normal.x.to_f * distance,
                normal.y.to_f * distance,
                normal.z.to_f * distance
            )
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Overrides — Cursor, Axis Lock and Stage Control
        # -----------------------------------------------------------------------------

        # -----------------------------------------------------------------------------
        # REGION | State Containment
        # -----------------------------------------------------------------------------

        # FUNCTION | This Tool Has Exactly Two States
        # ------------------------------------------------------------
        # The shared mixin drives a three-stage machine (idle > picking_b >
        # picking_depth) because the shape tools sweep a rectangle before they
        # extrude. Push/pull has no rectangle stage and no :picking_b branch
        # anywhere in it, so being put into that state kills the tool outright:
        # clicks match no branch, Enter matches no branch, and only ESC gets out.
        #
        # That is reachable today — the inherited BKSP/DEL handler calls
        # step_back, which demotes :picking_depth to :picking_b. Rather than trust
        # every inherited path to respect a state this tool cannot service, any
        # unknown state is snapped straight back to idle.
        # ------------------------------------------------------------
        def na_drawn__ensure_known_state
            return true if @na_state == :idle || @na_state == :picking_depth

            na_drawn__trace("recovered from unsupported state #{@na_state.inspect}")
            na_drawn__reset_pick_state
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Backspace Releases the Face, It Does Not Half-Retreat
        # A push either has a face or it does not; there is no intermediate stage
        # to fall back to, so the mixin's demotion to :picking_b is replaced.
        # ------------------------------------------------------------
        def na_drawn__step_back(view)
            released = na_drawn__release_last_lock

            unless released
                na_drawn__trace('step back — releasing the grabbed face')
                na_drawn__reset_pick_state
            end

            na_drawn__update_cursor(view, @na_last_mouse_x, @na_last_mouse_y) if released
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
        end
        # ---------------------------------------------------------------

        # FUNCTION | Enter Places the Push
        # Overridden so it can never be routed at a stage this tool does not have.
        # ------------------------------------------------------------
        def onReturn(view)
            return false unless na_drawn__ensure_known_state
            return false unless @na_state == :picking_depth

            na_drawn__trace('onReturn — placing')
            na_drawn__commit_push(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Double Click Places the Push
        # ------------------------------------------------------------
        def onLButtonDoubleClick(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return false unless na_drawn__ensure_known_state
            return false unless @na_state == :picking_depth

            na_drawn__trace('onLButtonDoubleClick — placing')
            na_drawn__update_cursor(view, x, y)
            na_drawn__commit_push(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Overrides — Cursor Tracking
        # -----------------------------------------------------------------------------

        # FUNCTION | Track the Push Distance, Picking Nothing While Doing It
        # ------------------------------------------------------------
        # This replaces the mixin's generic version, whose last line is
        #
        #     resolved ||= na_drawn__input_point_position(view, x, y)
        #
        # For the shape tools that fallback is harmless — the InputPoint is their
        # normal cursor source anyway. Here it is the bug: any frame where the
        # ray-to-line solve returns nil silently re-picks against whatever face
        # happens to be under the cursor and turns ITS inferred point into a push
        # distance. That is the "it keeps grabbing other faces while I drag, and
        # the distance jumps" behaviour, and because the solve only fails on some
        # frames it looked intermittent rather than broken.
        #
        # Once a face is grabbed, nothing is picked again unless CTRL explicitly
        # asks for vertex inference. The distance is pure ray-to-line maths, and a
        # frame that cannot be solved keeps the previous distance rather than
        # inventing a new one.
        # ------------------------------------------------------------
        def na_drawn__update_cursor(view, x, y)
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            return false unless @na_state == :picking_depth && @na_point_a

            resolved =
                if @na_ctrl_held
                    na_drawn__input_point_position(view, x, y)                # <-- Deliberate vertex snapping only
                else
                    na_drawn__depth_point_from_ray(view, x, y)
                end

            return false unless resolved                                      # <-- Hold the last good distance

            @na_cursor_raw     = resolved
            @na_cursor_snapped = resolved
            na_drawn__recalculate_sizes
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Project the Pick Ray onto the Push Direction
        # ------------------------------------------------------------
        def na_drawn__depth_point_from_ray(view, x, y)
            direction = na_drawn__push_direction
            return nil unless direction && @na_point_a

            ray     = view.pickray(x, y)
            closest = Geom.closest_points([@na_point_a, direction], ray)
            return nil unless closest && closest[0]

            na_drawn__point_in_front_of_ray?(ray, closest[0]) ? closest[0] : nil
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measure the Drag Along the Push Direction
        # The raw cursor point is used and the TRAVEL is snapped, rather than
        # snapping the point first — see the note at the top of this file.
        # ------------------------------------------------------------
        def na_drawn__recalculate_sizes
            return unless @na_state == :picking_depth
            return if na_drawn__locked?(:d)
            return unless @na_point_a && @na_cursor_raw

            direction = na_drawn__push_direction
            return unless direction

            travel     = (@na_cursor_raw - @na_point_a).dot(direction).to_f
            snapped    = na_drawn__snap_distance(travel).to_f
            @na_sign_d = snapped < 0.0 ? -1.0 : 1.0
            @na_size_d = snapped.abs
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arrow Keys Lock the Measured Axis
        # ------------------------------------------------------------
        def na_drawn__apply_axis_lock(axis, view)
            previous      = @na_axis_lock
            @na_axis_lock = (@na_axis_lock == axis) ? nil : axis

            if @na_axis_lock && @na_pp_target && !na_drawn__axis_lock_usable?
                @na_axis_lock = previous
                UI.beep
                Sketchup::set_status_text(
                    "This face is edge-on to #{NA_DRAWN_AXIS_LABELS[axis]} — it cannot travel along it",
                    SB_PROMPT
                )
                return false
            end

            na_drawn__after_axis_lock_changed(view)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Axis Ray Runs Through the Grabbed Point
        # ------------------------------------------------------------
        def na_drawn__axis_ray_origin
            @na_point_a
        end
        # ---------------------------------------------------------------

        # FUNCTION | TAB Has No Plane to Cycle Here
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            Sketchup::set_status_text('Use the arrow keys to lock the push axis', SB_PROMPT)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            ''
        end
        # ---------------------------------------------------------------

        # FUNCTION | Describe the Push Direction Rather Than a Drawing Plane
        # ------------------------------------------------------------
        def na_drawn__plane_description
            return 'No face grabbed' unless @na_pp_target

            "In #{Na__InsertPrimatives.Na__DeepPick__PathLabel(@na_pp_target)}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Nothing to Revise — a Pushed Face Has Already Moved
        # ------------------------------------------------------------
        def na_drawn__revise_available?
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Return to Hovering
        # ------------------------------------------------------------
        def na_drawn__reset_pick_state
            super
            na_drawn__clear_target
            @na_size_d = 0.0
            @na_sign_d = 1.0
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Mouse — Grab a Face, Then Push It
        # -----------------------------------------------------------------------------

        # ON MOUSE MOVE | Hover Highlight While Idle, Distance While Pushing
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            na_drawn__ensure_known_state
            @na_last_mouse_x = x
            @na_last_mouse_y = y

            if @na_state == :idle
                na_drawn__hover_face(view, x, y)
            else
                na_drawn__update_cursor(view, x, y)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Track Whichever Face Is Under the Cursor
        # ------------------------------------------------------------
        def na_drawn__hover_face(view, x, y)
            target = Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)

            if target.nil?
                na_drawn__clear_target
                return false
            end

            na_drawn__adopt_target(target)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cheap Fingerprint of a Face's Identity AND Position
        # entityID alone is not enough: pushpull MOVES a face and keeps its id, so
        # an id-only check happily reuses triangles cached before the push and
        # draws the highlight where the face used to be. A vertex position is what
        # makes a moved face read as different, and reading one vertex is nothing
        # next to re-triangulating the whole mesh.
        # ------------------------------------------------------------
        def na_drawn__target_fingerprint(target)
            return nil unless target

            face = target[:face]
            return nil unless face && face.valid?

            vertices = face.vertices
            return nil if vertices.empty?

            [
                face.entityID,
                vertices.length,
                vertices.first.position.to_a,
                target[:transformation].to_a
            ]
        rescue StandardError
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This the Same Face, Unmoved, That We Already Cached?
        # ------------------------------------------------------------
        def na_drawn__same_target?(target)
            return false if @na_pp_triangles.nil? || @na_pp_triangles.empty?
            return false unless @na_pp_fingerprint

            fresh = na_drawn__target_fingerprint(target)
            return false unless fresh

            fresh == @na_pp_fingerprint
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cache the Face Geometry in World Space
        # Rebuilt only when the picked face actually changes. Hovering calls this
        # on every mouse move, and triangulating a face, transforming every vertex
        # and re-measuring its area at that rate is what made the tool feel like it
        # was lagging a beat behind the cursor.
        # ------------------------------------------------------------
        def na_drawn__adopt_target(target)
            if na_drawn__same_target?(target)
                @na_pp_target = target                                        # <-- Keep the fresh path, reuse the cached geometry
                return false
            end

            @na_pp_target      = target
            @na_pp_triangles   = Na__InsertPrimatives.Na__DeepPick__WorldTriangles(target[:face], target[:transformation])
            @na_pp_loop        = Na__InsertPrimatives.Na__DeepPick__WorldOuterLoop(target[:face], target[:transformation])
            @na_pp_area        = Na__InsertPrimatives.Na__DeepPick__WorldAreaM2(target[:face], target[:transformation])
            @na_pp_fingerprint = na_drawn__target_fingerprint(target)
            true
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON DOWN | Grab a Face, or Place the Push
        # ------------------------------------------------------------
        def onLButtonDown(flags, x, y, view)
            @na_vcb_typing_active = false
            na_drawn__sync_modifier(flags)
            na_drawn__ensure_known_state
            @na_last_mouse_x = x                                              # <-- grab_face uses these as the press origin
            @na_last_mouse_y = y
            na_drawn__trace("onLButtonDown")

            case @na_state
            when :idle
                na_drawn__grab_face(view, x, y)
            when :picking_depth
                @na_drag_press_active = false
                na_drawn__update_cursor(view, x, y)
                na_drawn__commit_push(view)
            end

            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take Hold of the Face Under the Cursor
        # ------------------------------------------------------------
        def na_drawn__grab_face(view, x, y)
            target = Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)

            unless target
                UI.beep
                na_drawn__trace('grab refused — no face under the cursor')
                Sketchup::set_status_text('No face under the cursor', SB_PROMPT)
                return false
            end

            if target[:locked]
                UI.beep
                Sketchup::set_status_text('That face is inside a locked group or component', SB_PROMPT)
                return false
            end

            na_drawn__adopt_target(target)

            @na_ip.pick(view, x, y)
            @na_point_a = @na_ip.position || Na__InsertPrimatives.Na__DeepPick__WorldOuterLoop(target[:face], target[:transformation]).first
            return false unless @na_point_a

            @na_ip_origin.copy!(@na_ip)
            na_drawn__clear_locks
            @na_state  = :picking_depth
            @na_size_d = 0.0
            @na_sign_d = 1.0

            # Arms press-drag-release, so a face can be grabbed and pushed in one
            # gesture as well as click-move-click, matching the native tool.
            @na_drag_press_active = true
            @na_press_x           = @na_last_mouse_x
            @na_press_y           = @na_last_mouse_y

            na_drawn__warn_if_shared(target)
            na_drawn__trace('face grabbed')
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Say So When the Push Will Change Every Copy
        # ------------------------------------------------------------
        def na_drawn__warn_if_shared(target)
            count = target[:shared_count].to_i
            return false if count <= 1

            Sketchup::set_status_text(
                "Heads up: this definition has #{count} instances — pushing changes all of them",
                SB_PROMPT
            )
            puts "NA PUSH/PULL: shared definition, #{count} instances will change"
            true
        end
        # ---------------------------------------------------------------

        # ON LEFT BUTTON UP | Press-Drag-Release Places the Push Too
        # ------------------------------------------------------------
        def onLButtonUp(flags, x, y, view)
            na_drawn__sync_modifier(flags)
            return unless @na_state == :picking_depth
            return unless @na_drag_press_active

            @na_drag_press_active = false
            travelled_px = (x.to_f - @na_press_x.to_f).abs + (y.to_f - @na_press_y.to_f).abs
            return if travelled_px < NA_DRAWN_DRAG_MIN_PX

            na_drawn__update_cursor(view, x, y)
            na_drawn__commit_push(view)
            na_drawn__update_status_text
            na_drawn__refresh_vcb
            view.invalidate
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Drag Completion
        # -----------------------------------------------------------------------------

        # FUNCTION | Never Reached — This Tool Has No Rectangle Stage
        # ------------------------------------------------------------
        def na_drawn__advance_from_b(view)
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Distance Settled — Push the Face
        # ------------------------------------------------------------
        def na_drawn__advance_from_depth(view)
            na_drawn__commit_push(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Preview
        # -----------------------------------------------------------------------------

        # FUNCTION | Points the Preview Occupies, for the Draw Extents
        # ------------------------------------------------------------
        def na_drawn__preview_points
            return [] if @na_pp_loop.nil? || @na_pp_loop.empty?
            return @na_pp_loop unless @na_state == :picking_depth

            offset = na_drawn__push_offset_vector
            return @na_pp_loop unless offset

            @na_pp_loop + @na_pp_loop.map { |point| point.offset(offset) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Highlight the Hovered Face, or Preview the Push
        # ------------------------------------------------------------
        def na_drawn__draw_preview(view)
            na_drawn__draw_push_preview(view)
        end
        # ---------------------------------------------------------------

        # DRAW | Hover Highlight and Push Preview
        # The mixin's draw only calls the preview once a drag is running, but
        # this tool has something to show while idle too, so draw is taken over.
        # ------------------------------------------------------------
        def draw(view)
            @na_ip.draw(view) if na_drawn__inference_visible? && @na_ip && @na_ip.valid?
            Na__InsertPrimatives.Na__DrawnPreview__DrawAxisRay(view, na_drawn__axis_ray_origin, @na_axis_lock)

            if @na_state == :idle
                na_drawn__draw_hover(view)
                return
            end

            na_drawn__draw_push_preview(view)
            Na__InsertPrimatives.Na__DrawnPreview__DrawCrosshair(view, @na_point_a, nil, NA_DRAWN_ANCHOR_COLOR)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Shade the Face Under the Cursor
        # ------------------------------------------------------------
        def na_drawn__draw_hover(view)
            return if @na_pp_triangles.nil? || @na_pp_triangles.empty?

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, @na_pp_triangles, NA_PP_HOVER_FILL)
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, @na_pp_loop, NA_PP_HOVER_BORDER)

            return if @na_pp_loop.empty?
            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(
                view, @na_pp_loop.first,
                ["#{@na_pp_area} m2 face", Na__InsertPrimatives.Na__DeepPick__PathLabel(@na_pp_target)]
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | Preview the Face at Its Pushed Position
        # ------------------------------------------------------------
        def na_drawn__draw_push_preview(view)
            return if @na_pp_loop.nil? || @na_pp_loop.empty?

            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, @na_pp_loop, NA_PP_HOVER_BORDER, 1)

            offset = na_drawn__push_offset_vector
            unless offset && Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, @na_pp_triangles, NA_PP_HOVER_FILL)
                return
            end

            moved_triangles = @na_pp_triangles.map { |points| points.map { |point| point.offset(offset) } }
            moved_loop      = @na_pp_loop.map { |point| point.offset(offset) }

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, moved_triangles, NA_PP_RESULT_FILL)
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, moved_loop, NA_PP_RESULT_BORDER)

            @na_pp_loop.each_with_index do |point, index|
                view.drawing_color = NA_PP_RESULT_BORDER
                view.line_width    = 1
                view.draw_line(point, moved_loop[index])
            end

            na_drawn__draw_distance_label(view, moved_loop)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Label the Push Distance on the Travel Edge
        # ------------------------------------------------------------
        def na_drawn__draw_distance_label(view, moved_loop)
            anchor = @na_pp_loop.first
            moved  = moved_loop.first
            locked = na_drawn__locked?(:d)

            Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(
                view, anchor, moved,
                Na__InsertPrimatives.Na__DrawnPreview__DimensionText(@na_size_d, locked),
                @na_axis_lock ? Na__InsertPrimatives.Na__DrawnPreview__AxisColor(@na_axis_lock) :
                                Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(locked)
            )

            lines = ["Push #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs} mm"]
            if @na_axis_lock
                along = Na__InsertPrimatives.Na__DrawnFormat__Mm(na_drawn__world_normal_travel).abs
                lines << "along #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]} · #{along} mm on the face normal"
            else
                lines << "#{@na_pp_area} m2 face"
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, moved, lines)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            if @na_state == :picking_depth
                distance = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
                text     = na_drawn__locked?(:d) ? "[#{distance}]" : distance.to_s
                return "Push #{text} mm — release or click to place"
            end

            return "Face #{@na_pp_area} m2 — click to grab it" if @na_pp_target
            'Hover a face to push, at any nesting depth'
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            return ['Push distance', ''] if @na_state != :picking_depth

            ['Push distance', na_drawn__format_sizes([@na_size_d])]
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Measurements Box Entry
        # -----------------------------------------------------------------------------

        # FUNCTION | A Typed Distance Pins and Places
        # ------------------------------------------------------------
        def na_drawn__handle_vcb_text(text, view)
            unless @na_state == :picking_depth
                UI.beep
                Sketchup::set_status_text('Grab a face before typing a distance', SB_PROMPT)
                return false
            end

            tokens = Na__InsertPrimatives.Na__DrawnVcb__ParseEntry(text)
            raise ArgumentError, 'push takes a single distance' if tokens.length > 1

            distances = Na__InsertPrimatives.Na__DrawnVcb__ResolveAgainst(tokens, [@na_size_d])
            Na__InsertPrimatives.Na__DrawnVcb__ValidatePositive(distances, ['Distance'])

            @na_size_d = distances[0]
            na_drawn__lock_slot(:d)
            na_drawn__commit_push(view)
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Geometry Commit
        # -----------------------------------------------------------------------------

        # FUNCTION | Push the Grabbed Face
        # The distance handed to pushpull is LOCAL to the face's own definition,
        # so the world travel is divided by the scale the instance path applies
        # along that normal. Without it a push inside a scaled component would
        # overshoot by exactly that scale factor.
        # ------------------------------------------------------------
        def na_drawn__commit_push(view)
            target = @na_pp_target

            unless target && target[:face] && target[:face].valid?
                UI.beep
                Sketchup::set_status_text('That face is no longer available', SB_PROMPT)
                na_drawn__reset_pick_state
                return false
            end

            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                UI.beep
                na_drawn__trace('placement refused — zero distance')
                Sketchup::set_status_text('No push distance — drag further or type one', SB_PROMPT)
                return false
            end

            unless na_drawn__axis_lock_usable?
                UI.beep
                Sketchup::set_status_text('This face cannot travel along the locked axis', SB_PROMPT)
                return false
            end

            world_travel   = na_drawn__world_normal_travel
            local_distance = world_travel / target[:normal_scale].to_f
            model          = Sketchup.active_model

            unless na_drawn__execute_push(model, target, local_distance)
                UI.beep
                Sketchup::set_status_text("Push failed: #{@na_pp_last_error}", SB_PROMPT)
                na_drawn__reset_pick_state
                return false
            end

            na_drawn__trace("placed #{Na__InsertPrimatives.Na__DrawnFormat__Mm(world_travel).abs}mm")
            na_drawn__log_push(target, world_travel, local_distance)
            na_drawn__reset_pick_state
            view.invalidate if view
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Run the Pushpull Inside the Face's Own Editing Context
        # ------------------------------------------------------------
        # THIS is what the whole saga came down to. Editing a definition's
        # entities from OUTSIDE its editing context leaves the model changed but
        # the instance's display cache stale: the push landed, the screen kept
        # showing the old shape until the tool exited — which is why ESC
        # "completed" it, why pushes appeared after a delay, and why picks found
        # real faces where nothing was drawn. invalidate_bounds only refreshes
        # the bounding box, not the render.
        #
        # The create tools never see this because they build into
        # active_entities, the open context, which SketchUp always repaints.
        # So this does what a user does by hand — enter the group, push, leave —
        # via model.active_path= (SketchUp 2020+). The user's own editing
        # context is saved and restored around it.
        #
        # active_path= refuses to run inside an open transaction, so the order
        # is strict: enter context, start_operation, pushpull, commit, restore.
        # KNOWN CAVEAT to verify in testing: programmatic context changes may
        # add their own undo steps around the push.
        # ------------------------------------------------------------
        def na_drawn__execute_push(model, target, local_distance)
            @na_pp_last_error = nil
            instances   = Na__InsertPrimatives.Na__DeepPick__Instances(target[:path])
            target_path = instances.empty? ? nil : instances
            entered     = false
            previous    = nil

            if model.respond_to?(:active_path=)
                begin
                    previous = model.active_path                              # <-- nil at root, else the user's context
                    unless na_drawn__same_context?(previous, target_path)
                        model.active_path = target_path
                        entered = true
                        na_drawn__trace("entered context #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}")
                    end
                rescue StandardError => error
                    entered = false
                    na_drawn__trace("context open failed (#{error.message}) — editing from outside")
                end
            end

            pushed = false

            # Undo chaining. Entering and leaving the context are undo steps of
            # their own, which is why a push unwound in three Ctrl+Z, with the
            # middle press teleporting the user back inside the group. When a
            # context was entered, the push op is started `transparent` (merging
            # it backwards into the enter step) and `next_transparent` (pulling
            # the restore step forwards into it), so enter-push-restore undoes as
            # ONE action. next_transparent is deprecated and dangerous when a
            # user action can slip in behind it — none can here: the restore runs
            # synchronously below, in this same call, before control returns.
            #
            # The flags are strictly conditional. Without a context change they
            # would merge the push into whatever the user did LAST, making their
            # next Ctrl+Z silently eat two unrelated actions.
            if entered
                model.start_operation('Deep Push Pull', true, true, true)
            else
                model.start_operation('Deep Push Pull', true)
            end

            begin
                target[:face].pushpull(local_distance)
                Na__InsertPrimatives.Na__DeepPick__InvalidateDefinitions(target[:path]) unless entered
                model.commit_operation
                pushed = true
            rescue StandardError => error
                model.abort_operation
                @na_pp_last_error = error.message
                na_drawn__trace("pushpull raised: #{error.message}")
            end

            na_drawn__restore_context(model, previous) if entered
            pushed
        end
        # ---------------------------------------------------------------

        # FUNCTION | Are Two Editing Contexts the Same Place?
        # ------------------------------------------------------------
        def na_drawn__same_context?(current, wanted)
            return true if current.nil? && wanted.nil?
            return false if current.nil? || wanted.nil?

            current.to_a == wanted.to_a
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put the User Back in the Context They Were In
        # Falls back to the model root rather than ever leaving them stranded
        # inside the group this tool opened.
        # ------------------------------------------------------------
        def na_drawn__restore_context(model, previous)
            model.active_path = previous
        rescue StandardError
            begin
                model.active_path = nil
            rescue StandardError
                nil
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Push
        # ------------------------------------------------------------
        def na_drawn__log_push(target, world_travel, local_distance)
            puts "\n"
            puts '----------------------------------------'
            puts 'DEEP PUSH/PULL APPLIED'
            puts "Target: #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            puts "Dragged: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm#{@na_axis_lock ? " along #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]}" : ' along the face normal'}"
            puts "Normal travel: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(world_travel).abs}mm world"
            puts "Local push   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(local_distance).abs}mm (instance scale #{format('%.4f', target[:normal_scale])})"
            puts "Instances affected: #{target[:shared_count]}"
            puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Public Entry Point
    # -----------------------------------------------------------------------------

    # FUNCTION | Is Push/Pull Console Tracing On?
    # ------------------------------------------------------------
    def self.Na__PushPull__Trace?
        @na_push_pull_trace == true
    end
    # ---------------------------------------------------------------

    # FUNCTION | Turn Push/Pull Console Tracing On or Off
    # ------------------------------------------------------------
    def self.Na__PushPull__SetTrace(enabled)
        @na_push_pull_trace = (enabled ? true : false)
        puts "NA PUSH/PULL trace #{@na_push_pull_trace ? 'ON' : 'OFF'}"
        @na_push_pull_trace
    end
    # ---------------------------------------------------------------

    # FUNCTION | Activate the Deep Push/Pull Tool (Hotkey Entry Point)
    # ------------------------------------------------------------
    def self.Na__InsertPrimatives__DeepPushPull
        Na__InsertPrimatives.Na__ModeSwitch__ActivateDrawnPushPullTool
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF DEEP PUSH PULL TOOL MODULE
# =============================================================================
