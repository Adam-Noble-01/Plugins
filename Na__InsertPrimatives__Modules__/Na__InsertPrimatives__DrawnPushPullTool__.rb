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
# TAB — QUAD MODE:
# - SketchUp's push welds the new wall into the coplanar wall it grew out of and
#   deletes the edge where they met. That is usually what you want and is
#   exactly what you do not want when the extrusion is a run of wall: the corner
#   you meant to make has no line to turn at.
# - TAB arms QUAD mode, which re-draws that start loop as edges after the push —
#   edges only, never a face, so the solid stays hollow and stays a solid. Two
#   pushes in different directions then meet on a real quad corner.
# - The setting is remembered between sessions, so the mode is a preference the
#   user sets once, not something to re-arm on every face.
#
# SHIFT — SLOPE MODE:
# - pushpull only ever extrudes along the face normal, and on the plumb-cut end
#   of a roof that normal is horizontal. Push it and the roof gets longer on
#   plan while the rake it was cut to is thrown away.
# - SHIFT swaps the normal for the direction that CONTINUES THE NEIGHBOURING
#   FACE'S PLANE, so the roof runs on down its own pitch with its end cut still
#   plumb. The neighbour is chosen and the maths is done in Na__SlopePush__;
#   this tool only asks for a direction and travels along it.
# - Held, not toggled, and inert on geometry with no trajectory to continue —
#   a box says so in the status bar and pushes normally.
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
require_relative 'Na__InsertPrimatives__DrawnSlopePush__'

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
        NA_PP_QUAD_BORDER     = Sketchup::Color.new(200,  60, 200, 255)   # <-- The line quad mode will leave behind

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
                 "ctrl=#{@na_ctrl_held ? 'on' : 'off'} shift=#{@na_shift_held ? 'on' : 'off'} " \
                 "slope=#{na_drawn__slope_mode? ? 'on' : 'off'} axis=#{@na_axis_lock.inspect}"
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
            @na_pp_quad_stats  = nil
            @na_pp_slope       = nil                                          # <-- The SHIFT trajectory for THIS face, or nil
            @na_pp_seam_healed = 0
            @na_pp_stretched   = false
            @na_pp_split       = nil
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
                'Hold SHIFT to push along the NEIGHBOURING face instead — a roof runs on down its own rake',
                'TAB toggles QUAD mode — the extrusion keeps its start loop as edges, no face',
                'With QUADS on, dragging INWARDS cuts an inset edge loop instead of shortening',
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

        # FUNCTION | Is SHIFT Actually Buying Anything on This Face?
        # ------------------------------------------------------------
        # Held SHIFT alone is not slope mode. The face also has to have a
        # neighbour worth following, and a box does not — so on a box SHIFT is
        # inert, the push stays normal, and the status line says why rather
        # than leaving the user pressing a key that does nothing.
        # ------------------------------------------------------------
        def na_drawn__slope_mode?
            @na_shift_held && !@na_pp_slope.nil?
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Trajectory SHIFT Is Following, or nil
        # ------------------------------------------------------------
        def na_drawn__slope_direction
            na_drawn__slope_mode? ? @na_pp_slope[:direction] : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Direction the Face Actually Travels
        # ------------------------------------------------------------
        # The face normal, or in slope mode the neighbour's continuation. This
        # is the ONE place the two modes differ: everything below measures,
        # previews, snaps and commits against whatever this returns, so slope
        # mode needed no second copy of any of it.
        # ------------------------------------------------------------
        def na_drawn__travel_direction
            na_drawn__slope_direction || na_drawn__face_normal
        end
        # ---------------------------------------------------------------

        # FUNCTION | Direction the Drag Is Measured Along
        # ------------------------------------------------------------
        def na_drawn__push_direction
            locked = @na_axis_lock ? Na__InsertPrimatives.Na__DrawnGrid__AxisVector(@na_axis_lock) : nil
            locked || na_drawn__travel_direction
        end
        # ---------------------------------------------------------------

        # FUNCTION | How Much of the Locked Axis the Travel Direction Carries
        # This is the cosine between the two, and the divisor that converts a
        # distance along the axis into a distance along the travel.
        # ------------------------------------------------------------
        def na_drawn__axis_travel_factor
            travel = na_drawn__travel_direction
            axis   = @na_axis_lock ? Na__InsertPrimatives.Na__DrawnGrid__AxisVector(@na_axis_lock) : nil
            return 1.0 unless travel && axis

            axis.dot(travel).to_f
        end
        # ---------------------------------------------------------------

        # FUNCTION | Can the Face Move Along the Locked Axis at All?
        # ------------------------------------------------------------
        def na_drawn__axis_lock_usable?
            return true unless @na_axis_lock

            na_drawn__axis_travel_factor.abs >= NA_PP_MIN_AXIS_FACTOR
        end
        # ---------------------------------------------------------------

        # FUNCTION | Signed World Distance the Face Travels Along Its Direction
        # ------------------------------------------------------------
        def na_drawn__world_travel_distance
            travel = na_drawn__signed_d
            return travel unless @na_axis_lock

            factor = na_drawn__axis_travel_factor
            return 0.0 if factor.abs < NA_PP_MIN_AXIS_FACTOR

            travel / factor
        end
        # ---------------------------------------------------------------

        # FUNCTION | World Offset Vector Applied to the Preview Face
        # ------------------------------------------------------------
        def na_drawn__push_offset_vector
            direction = na_drawn__travel_direction
            return nil unless direction

            distance = na_drawn__world_travel_distance
            Geom::Vector3d.new(
                direction.x.to_f * distance,
                direction.y.to_f * distance,
                direction.z.to_f * distance
            )
        end
        # ---------------------------------------------------------------

        # FUNCTION | That Same Offset in the Face's Own Definition Space
        # ------------------------------------------------------------
        # Two points rather than the vector: a direction is only a difference of
        # positions, and transforming positions cannot be caught out by how a
        # translation is or is not applied to a bare vector. For a plain normal
        # push this comes back as the normal times the old local_distance, which
        # is exactly what pushpull was being given before slope mode existed.
        # ------------------------------------------------------------
        def na_drawn__local_offset_vector(target)
            offset = na_drawn__push_offset_vector
            return nil unless offset && target

            inverse = target[:transformation].inverse
            origin  = Geom::Point3d.new(0, 0, 0)
            ahead   = origin.offset(offset)

            ahead.transform(inverse) - origin.transform(inverse)
        rescue StandardError
            nil
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

        # FUNCTION | TAB Toggles Quad Mode
        # There is no drawing plane to cycle in this tool, so TAB is free, and
        # this is the one modifier that has to be reachable mid-drag: it changes
        # what the SAME push produces, and the preview redraws to show it.
        # ------------------------------------------------------------
        def na_drawn__cycle_plane_lock(view)
            enabled = Na__InsertPrimatives.Na__DrawnSettings__ToggleQuadPush
            na_drawn__trace("quad mode #{enabled ? 'ON' : 'OFF'}")

            Sketchup::set_status_text(
                enabled ? 'QUAD mode ON — the push keeps its start loop as edges' :
                          'QUAD mode OFF — the push merges into the wall it extends',
                SB_PROMPT
            )
            @na_last_status_text = nil                                        # <-- Let the composed line replace this notice
            na_drawn__refresh_vcb
            view.invalidate if view
            enabled
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is the Quad Ring Armed?
        # ------------------------------------------------------------
        def na_drawn__quad_mode?
            Na__InsertPrimatives.Na__DrawnSettings__QuadPushEnabled?
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is This Drag Going to Cut a Loop Instead of Pushing?
        # Quads armed and travelling INTO the material. The preview and the
        # commit both ask this same question of the same module, so they cannot
        # disagree about which of the two the user is about to get.
        # ------------------------------------------------------------
        def na_drawn__loop_cut_mode?
            Na__InsertPrimatives.Na__EdgeLoops__IsCut?(na_drawn__quad_mode?, na_drawn__world_travel_distance)
        end
        # ---------------------------------------------------------------

        # FUNCTION | What TAB Does in This Tool
        # ------------------------------------------------------------
        def na_drawn__tab_hint
            "TAB quads #{na_drawn__quad_mode? ? 'ON' : 'OFF'}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Describe the Push Direction Rather Than a Drawing Plane
        # ------------------------------------------------------------
        def na_drawn__plane_description
            return 'No face grabbed' unless @na_pp_target
            return 'Loose geometry face' if @na_pp_target[:depth].to_i.zero?

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
        # The one statement this tool gained for the 2D variant. A parallel camera
        # cannot work this tool at all — the wall you want is edge-on and there
        # is no face to hover — so switching to a 2D scene tab hands over to
        # DrawnPushPull2dTool on the next idle mouse move. Inert when that
        # module is not loaded, and it never fires mid-drag.
        # ------------------------------------------------------------
        def onMouseMove(flags, x, y, view)
            return if defined?(Na__InsertPrimatives::DrawnPushPull2dTool) &&
                      Na__InsertPrimatives.Na__PushPull2d__HandoverIfCameraFlipped(self, view, @na_state)

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
            @na_pp_slope       = Na__InsertPrimatives.Na__SlopePush__Best(target)
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

            # Backstop only. Locked geometry is skipped by the picker itself, so
            # a locked target should never reach this far — but a refusal is a
            # far better failure than editing something the user locked.
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

            quads = na_drawn__quad_mode?

            # The outline carries the mode before the grab, not after it. TAB is
            # a state you can be in without realising, and on a face that has no
            # wall to divide the result looks identical either way — so the
            # answer to "am I in quad mode" has to be on the face you are
            # pointing at, whatever it is nested in.
            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, @na_pp_triangles, NA_PP_HOVER_FILL)
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(
                view, @na_pp_loop,
                quads ? NA_PP_QUAD_BORDER : NA_PP_HOVER_BORDER,
                quads ? 3 : 2
            )

            return if @na_pp_loop.empty?

            lines = ["#{@na_pp_area} m2 face", Na__InsertPrimatives.Na__DeepPick__PathLabel(@na_pp_target)]
            lines << 'QUADS — keeps the start loop' if quads

            if na_drawn__slope_mode?
                lines << "SHIFT SLOPE — #{Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope)}"
            elsif @na_pp_slope
                lines << "SHIFT — follow the #{Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope)} neighbour"
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, @na_pp_loop.first, lines)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Preview the Face at Its Pushed Position
        # ------------------------------------------------------------
        def na_drawn__draw_push_preview(view)
            return if @na_pp_loop.nil? || @na_pp_loop.empty?

            # In quad mode the start loop is not just where the face was, it is
            # geometry the push will leave behind — so it is drawn as the thing
            # it is about to become rather than as a faded memory.
            if na_drawn__quad_mode?
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, @na_pp_loop, NA_PP_QUAD_BORDER, 3)
            else
                Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, @na_pp_loop, NA_PP_HOVER_BORDER, 1)
            end

            offset = na_drawn__push_offset_vector
            unless offset && Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, @na_pp_triangles, NA_PP_HOVER_FILL)
                return
            end

            if na_drawn__loop_cut_mode?
                na_drawn__draw_loop_cut_preview(view, offset)
                return
            end

            moved_triangles = @na_pp_triangles.map { |points| points.map { |point| point.offset(offset) } }
            moved_loop      = @na_pp_loop.map { |point| point.offset(offset) }

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, moved_triangles, NA_PP_RESULT_FILL)
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, moved_loop, NA_PP_RESULT_BORDER)

            # Drawn here rather than through the preview module, so the pair of
            # loops has to be converted to draw space by hand.
            side_from = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(@na_pp_loop)
            side_to   = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(moved_loop)

            side_from.each_with_index do |point, index|
                view.drawing_color = NA_PP_RESULT_BORDER
                view.line_width    = 1
                view.draw_line(point, side_to[index])
            end

            na_drawn__draw_travel_arrow(view, offset)
            na_drawn__draw_distance_label(view, moved_loop)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Preview a Loop Cut — Nothing Moves, a Line Appears
        # ------------------------------------------------------------
        # Showing the ordinary push preview here would be a lie: it shades the
        # face at its new position in result orange, which reads as "the solid
        # is about to end HERE". On this path the solid does not move at all.
        # So the face is left drawn where it is, and the only thing put at the
        # inset position is the ring itself, in the quad colour, because a line
        # is genuinely all that is going to be created.
        # ------------------------------------------------------------
        def na_drawn__draw_loop_cut_preview(view, offset)
            cut_loop = @na_pp_loop.map { |point| point.offset(offset) }

            Na__InsertPrimatives.Na__DrawnPreview__DrawTriangles(view, @na_pp_triangles, NA_PP_HOVER_FILL)
            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, @na_pp_loop, NA_PP_HOVER_BORDER, 1)

            # The inset distance, shown as the strip it measures across.
            strip_from = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(@na_pp_loop)
            strip_to   = Na__InsertPrimatives.Na__DrawnPreview__ToDrawSpace(cut_loop)

            strip_from.each_with_index do |point, index|
                view.drawing_color = NA_PP_QUAD_BORDER
                view.line_width    = 1
                view.draw_line(point, strip_to[index])
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawLoop(view, cut_loop, NA_PP_QUAD_BORDER, 3)

            na_drawn__draw_travel_arrow(view, offset)
            na_drawn__draw_distance_label(view, cut_loop)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Point an Arrow the Way the Face Is Actually Travelling
        # ------------------------------------------------------------
        # Taken from the OFFSET rather than from the face normal, so it flips to
        # point into the solid on a negative push. An axis lock changes what the
        # drag MEASURES and never where the face goes, so the arrow must not
        # follow the locked axis either — it follows the travel.
        # ------------------------------------------------------------
        def na_drawn__draw_travel_arrow(view, offset)
            return unless @na_point_a && offset && offset.length > 0

            Na__InsertPrimatives.Na__DrawnPreview__DrawDirectionArrow(view, @na_point_a, offset.normalize)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Label the Push Distance on EVERY Travel Edge
        # ------------------------------------------------------------
        # One label on one corner left the other three corners of a pushed wall
        # unmeasured, and WHICH corner got it came down to loop order rather than
        # to anything the user could see or choose. Every travel edge is
        # labelled instead.
        #
        # THE OVERLAP CULL IS WHAT MAKES "EVERY" SAFE:
        # - A rectangle has four travel edges and all four get labelled, which is
        #   the case this was asked for. A pushed circle has as many as it has
        #   segments, and two dozen copies of one number piled on each other is
        #   worse than the single label this replaced. So a label is skipped when
        #   it would land within NA_DRAWN_LABEL_MIN_GAP_PX of one already placed.
        # - Positions are compared in SCREEN space. Whether two labels collide is
        #   a question about the viewport, and two corners far apart in the model
        #   can project onto the same pixels.
        # ------------------------------------------------------------
        def na_drawn__draw_distance_label(view, moved_loop)
            locked = na_drawn__locked?(:d)
            text   = Na__InsertPrimatives.Na__DrawnPreview__DimensionText(@na_size_d, locked)
            color  = @na_axis_lock ? Na__InsertPrimatives.Na__DrawnPreview__AxisColor(@na_axis_lock) :
                                     Na__InsertPrimatives.Na__DrawnPreview__DimensionColor(locked)
            placed = []

            @na_pp_loop.each_with_index do |point, index|
                moved_point = moved_loop[index]
                next unless moved_point
                next unless na_drawn__claim_label_slot(view, point, moved_point, placed)

                Na__InsertPrimatives.Na__DrawnPreview__DrawEdgeLabel(view, point, moved_point, text, color)
            end

            moved    = moved_loop.first
            distance = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs

            lines =
                if na_drawn__loop_cut_mode?
                    ["Loop cut #{distance} mm inset"]                          # <-- "(quads)" is redundant; a cut only happens with them on
                else
                    ["Push #{distance} mm#{na_drawn__quad_mode? ? '  (quads)' : ''}"]
                end

            if @na_axis_lock
                along = Na__InsertPrimatives.Na__DrawnFormat__Mm(na_drawn__world_travel_distance).abs
                lines << "along #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]} · #{along} mm on the face normal"
            else
                lines << "#{@na_pp_area} m2 face"
            end

            Na__InsertPrimatives.Na__DrawnPreview__DrawWorldLabel(view, moved, lines)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Take a Screen Slot for a Travel Label, or Report It Taken
        # Mutates `placed` on success, so the caller's loop naturally thins a
        # dense run of corners down to the ones that can actually be read.
        # ------------------------------------------------------------
        def na_drawn__claim_label_slot(view, point, moved_point, placed)
            midpoint = Geom::Point3d.new(
                (point.x.to_f + moved_point.x.to_f) * 0.5,
                (point.y.to_f + moved_point.y.to_f) * 0.5,
                (point.z.to_f + moved_point.z.to_f) * 0.5
            )

            screen = view.screen_coords(
                Na__InsertPrimatives.Na__DrawnPreview__ToDrawPoint(midpoint)
            )
            wanted = [screen.x.to_f, screen.y.to_f]

            clash = placed.any? do |taken|
                dx = taken[0] - wanted[0]
                dy = taken[1] - wanted[1]
                Math.sqrt((dx * dx) + (dy * dy)) < NA_DRAWN_LABEL_MIN_GAP_PX
            end
            return false if clash

            placed << wanted
            true
        rescue StandardError
            false                                                             # <-- A slot that cannot be measured is not drawn
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------


        # -----------------------------------------------------------------------------
        # REGION | Subclass Contract — Status and Measurements Box
        # -----------------------------------------------------------------------------

        # FUNCTION | Middle Section of the Status Bar Line
        # ------------------------------------------------------------
        def na_drawn__status_detail
            quads = na_drawn__quad_mode? ? ' QUADS' : ''
            slope = na_drawn__slope_hint

            if @na_state == :picking_depth
                distance = Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs
                text     = na_drawn__locked?(:d) ? "[#{distance}]" : distance.to_s
                return "Loop cut #{text} mm inset — release or click to cut#{slope}" if na_drawn__loop_cut_mode?

                verb = na_drawn__slope_mode? ? 'Slope' : 'Push'
                return "#{verb}#{quads} #{text} mm — release or click to place#{slope}"
            end

            focus = na_drawn__focus_hint

            return "Face #{@na_pp_area} m2 — click to grab it#{quads}#{slope}#{focus}" if @na_pp_target
            "Hover a face to push, at any nesting depth#{quads}#{slope}#{focus}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Status Fragment for the SHIFT Trajectory
        # ------------------------------------------------------------
        # Three things to say and all three matter. SHIFT doing something says
        # what it is following. SHIFT doing nothing says WHY, because a modifier
        # that silently no-ops on a box is the kind of thing users decide is
        # broken. And with SHIFT up, a face that HAS a trajectory advertises it,
        # which is the only way anyone finds the feature at all.
        # ------------------------------------------------------------
        def na_drawn__slope_hint
            return " — SHIFT slope #{Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope)}" if na_drawn__slope_mode?
            return ' — SHIFT: no sloped neighbour to follow here' if @na_shift_held && @na_pp_target
            return '' unless @na_pp_slope

            " — SHIFT follows the #{Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope)} neighbour"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Measurements Box Label and Live Value
        # ------------------------------------------------------------
        def na_drawn__vcb_label_and_value
            label = na_drawn__slope_mode? ? 'Slope distance' : 'Push distance'
            return [label, ''] if @na_state != :picking_depth

            [label, na_drawn__format_sizes([@na_size_d])]
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

            world_travel = na_drawn__world_travel_distance
            local_offset = na_drawn__local_offset_vector(target)

            unless local_offset
                UI.beep
                Sketchup::set_status_text('That face could not be measured in its own space', SB_PROMPT)
                return false
            end

            model    = Sketchup.active_model
            cutting  = na_drawn__loop_cut_mode?                               # <-- Read before the commit; reporting below needs it
            sloped   = na_drawn__slope_mode?

            unless na_drawn__execute_push(model, target, local_offset)
                UI.beep
                Sketchup::set_status_text("Push failed: #{@na_pp_last_error}", SB_PROMPT)
                na_drawn__report_failure(target, local_offset, sloped)
                na_drawn__reset_pick_state
                return false
            end

            na_drawn__trace("placed #{Na__InsertPrimatives.Na__DrawnFormat__Mm(world_travel).abs}mm")
            na_drawn__log_push(target, world_travel, sloped)

            # A ring that went in and came straight back out is a silent failure
            # otherwise: the push looks right and the quad line simply is not
            # there. Say so where the user is already looking.
            if @na_pp_quad_stats && @na_pp_quad_stats[:misplaced]
                UI.beep
                Sketchup::set_status_text('Push placed, but the quad ring could not be positioned — see the console', SB_PROMPT)
                @na_last_status_text = nil
            end

            # A loop cut that kept nothing did nothing at all — the solid is
            # untouched and no line was left. Without this the gesture reads as
            # having simply been ignored, which is the hardest kind of failure
            # to diagnose from the viewport.
            if cutting && (@na_pp_quad_stats.nil? || @na_pp_quad_stats[:kept].to_i.zero?)
                UI.beep
                Sketchup::set_status_text(
                    'No loop cut — the faces around this one are not a clean sweep of it',
                    SB_PROMPT
                )
                @na_last_status_text = nil
            end

            # And the same for the outward ring. It only ever announced itself
            # when it landed in the wrong SPACE, so a ring that landed on top of
            # edges that were already there — building nothing, reporting them
            # as kept — passed in silence. A quad line that does not appear is
            # exactly as broken as one that lands in the wrong place.
            if na_drawn__quad_mode? && !cutting &&
               (@na_pp_quad_stats.nil? || @na_pp_quad_stats[:kept].to_i.zero?)
                UI.beep
                Sketchup::set_status_text(
                    'Push placed, but the quad line built nothing — see the console',
                    SB_PROMPT
                )
                @na_last_status_text = nil
            end

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
        def na_drawn__execute_push(model, target, local_offset)
            @na_pp_last_error = nil

            # The travel arrives as one local vector and is split here into the
            # part pushpull can do and the part it cannot. Off slope the second
            # part is a zero vector and this is the maths the tool always used.
            split          = Na__InsertPrimatives.Na__SlopePush__SplitOffset(target[:face], local_offset)
            local_distance = split[:distance]
            shear          = split[:shear]
            @na_pp_split   = split                                            # <-- Kept for the console report, which runs after the push

            instances      = Na__InsertPrimatives.Na__DeepPick__Instances(target[:path])
            target_path    = instances.empty? ? nil : instances
            entered        = false
            previous       = nil
            selected       = Na__InsertPrimatives.Na__DeepPick__FocusSnapshot(model)

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

            pushed  = false
            quads   = na_drawn__quad_mode?
            sheared = shear.length.to_f >= NA_SLOPE_PUSH_MIN_SHEAR
            cut     = Na__InsertPrimatives.Na__EdgeLoops__IsCut?(quads, local_distance)
            op_name = if    cut     then 'Deep Push Pull (Edge Loop)'
                      elsif sheared then 'Deep Push Pull (Slope)'
                      elsif quads   then 'Deep Push Pull (Quads)'
                      else               'Deep Push Pull'
                      end

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
                model.start_operation(op_name, true, true, true)
            else
                model.start_operation(op_name, true)
            end

            begin
                face   = target[:face]
                parent = face.parent

                # Read the start loops BEFORE the push — pushpull moves the face,
                # and these positions are the only record of where it began.
                loops    = quads ? Na__InsertPrimatives.Na__PushPull__CaptureLoops(face) : []
                entities = parent.respond_to?(:entities) ? parent.entities : model.active_entities

                @na_pp_quad_stats  = nil
                @na_pp_seam_healed = 0
                @na_pp_stretched   = false

                # Read before anything touches the entities: after the push the
                # normal cannot be asked of a face that may no longer be there,
                # and the interior point is what identifies the moved face.
                normal_local = sheared ? face.normal : nil
                interior     = sheared ? Na__InsertPrimatives.Na__SlopePush__InteriorPoint(face) : nil

                if cut
                    # LOOP CUT. Nothing is pushed at all — that is the whole
                    # point of the inward gesture. The ring is offset along the
                    # WHOLE travel, not just its normal share: in slope mode the
                    # faces around this one are the sweep of its loop along the
                    # slope, so that is the direction the cut has to follow to
                    # land in them. Off slope the two are the same vector.
                    ring_dir  = local_offset.length > 0 ? local_offset.normalize : face.normal
                    ring_step = local_offset.length.to_f
                    inset     = Na__InsertPrimatives.Na__EdgeLoops__OffsetLoops(loops, ring_dir, ring_step)
                    unless inset.empty?
                        build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, inset.first.first)
                        @na_pp_quad_stats = Na__InsertPrimatives.Na__EdgeLoops__Cut(
                            entities, loops, ring_dir, ring_step, build
                        )
                    end
                elsif sheared && interior &&
                      Na__InsertPrimatives.Na__SlopePush__CanStretch?(face, local_offset)
                    # SLOPE, THE CLEAN WAY. Every face touching this one contains
                    # the slope, so the face can simply be carried along it and
                    # they stretch to follow — exactly what selecting the end of
                    # the roof and moving it down the rake does by hand. Nothing
                    # is created, nothing is welded, and there is no seam left
                    # across the surface that was just made continuous.
                    #
                    # A refusal here is raised rather than swallowed. Falling
                    # through to an ordinary push would hand back geometry that
                    # does not match the preview, which is worse than nothing.
                    unless Na__InsertPrimatives.Na__SlopePush__Stretch(entities, face, local_offset)
                        raise 'the face would not move along the slope — no vertex transform took'
                    end

                    @na_pp_stretched = true
                    na_drawn__trace('slope: stretched the face along the neighbour')

                    unless loops.empty?
                        build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, loops.first.first)
                        @na_pp_quad_stats = Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, loops, build)
                    end
                else
                    face.pushpull(local_distance)

                    # SLOPE, THE GENERAL WAY. Something around this face does not
                    # contain the slope, so stretching would pull it out of its
                    # own plane. pushpull takes the normal's share instead and
                    # the sideways remainder is applied to the moved face alone,
                    # which turns every wall the push made from a rectangle into
                    # a parallelogram — still planar, whatever the neighbours are
                    # doing.
                    if sheared
                        travel = Geom::Vector3d.new(
                            normal_local.x.to_f * local_distance,
                            normal_local.y.to_f * local_distance,
                            normal_local.z.to_f * local_distance
                        )

                        moved = Na__InsertPrimatives.Na__SlopePush__MovedFace(
                            entities, face, interior, travel, normal_local
                        )

                        raise 'the pushed face could not be found again to shear it' unless moved

                        unless Na__InsertPrimatives.Na__SlopePush__ApplyShear(entities, moved, shear)
                            raise 'the pushed face would not shear — no vertex transform took'
                        end

                        face = moved                                          # <-- The seam heal below reads it too
                        na_drawn__trace('slope: pushed and sheared onto the neighbour')
                    end

                    unless loops.empty?
                        build = Na__InsertPrimatives.Na__DeepPick__AddTransform(model, entities, loops.first.first)
                        @na_pp_quad_stats = Na__InsertPrimatives.Na__PushPull__StitchQuadRing(entities, loops, build)
                    end

                    # A normal push welds its new wall into the coplanar one it
                    # grew from and deletes the line between them. A sheared one
                    # cannot — the wall only becomes coplanar once the shear has
                    # run, by which time the weld has already not happened. So
                    # the seam is cleared here instead, and only where it has
                    # genuinely become nothing. QUAD mode exists to KEEP that
                    # line, so this never runs there.
                    if sheared && !quads
                        @na_pp_seam_healed = Na__InsertPrimatives.Na__SlopePush__HealSeam(face)
                    end
                end

                Na__InsertPrimatives.Na__DeepPick__InvalidateDefinitions(target[:path]) unless entered
                model.commit_operation
                pushed = true
            rescue StandardError => error
                model.abort_operation
                @na_pp_last_error = error.message
                na_drawn__trace("pushpull raised: #{error.message}")
            end

            if entered
                na_drawn__restore_context(model, previous)

                # Opening the group cleared the user's selection, and that
                # selection is what tells the picker which group to favour. Put
                # it back or the focus dies on the first push of the session.
                Na__InsertPrimatives.Na__DeepPick__FocusRestore(model, selected)
            end

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

        # FUNCTION | Say Out Loud Why a Push Was Refused
        # ------------------------------------------------------------
        # na_drawn__trace is off by default and a status-bar line is gone by the
        # time anyone thinks to read it, so a refusal that produced NO geometry
        # printed nothing anybody would ever see. That is how slope mode came to
        # be reported as "the preview works and nothing is created", with no way
        # to tell which of four things had gone wrong.
        #
        # A failure is not chatter. It is the one thing always worth printing,
        # and it prints the numbers the next diagnosis needs rather than just
        # the message.
        # ------------------------------------------------------------
        def na_drawn__report_failure(target, local_offset, sloped)
            split = @na_pp_split || { :distance => 0.0, :shear => Geom::Vector3d.new(0, 0, 0) }

            puts "\n"
            puts '----------------------------------------'
            puts 'DEEP PUSH/PULL REFUSED'
            puts "Reason: #{@na_pp_last_error}"
            puts "Target: #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            puts "Mode  : #{sloped ? 'SLOPE' : 'normal'}#{na_drawn__quad_mode? ? ' + QUADS' : ''}"
            puts "Slope : #{sloped ? Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope) : 'n/a'}"
            puts "Offset: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(local_offset.length).abs}mm local"
            puts "Split : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(split[:distance]).abs}mm along the normal, " \
                 "#{Na__InsertPrimatives.Na__DrawnFormat__Mm(split[:shear].length).abs}mm sideways"
            puts "Route : #{@na_pp_stretched ? 'stretch' : 'pushpull + shear'}"
            puts '----------------------------------------'
        rescue StandardError => error
            puts "NA PUSH/PULL: refused, and the report itself failed (#{error.message})"
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Line Saying What the Quad Ring Actually Did
        # Kept edges are the quad lines that survived; swept ones are ring edges
        # that bounded nothing. An inward drag no longer reaches this report at
        # all — it is a loop cut, which keeps its own tally.
        # ------------------------------------------------------------
        def na_drawn__quad_report
            return 'off' unless na_drawn__quad_mode?
            return "LOOP CUT — #{Na__InsertPrimatives.Na__EdgeLoops__Report(@na_pp_quad_stats)}" if na_drawn__loop_cut_mode?

            stats = @na_pp_quad_stats
            return 'ON — no ring built' unless stats

            summary = "ON — #{stats[:kept]} edges kept, #{stats[:swept]} swept, #{stats[:faces_removed]} fill face(s) removed"
            summary << ' — RING LANDED IN THE WRONG SPACE, removed' if stats[:misplaced]
            summary
        end
        # ---------------------------------------------------------------

        # FUNCTION | Console Report for a Completed Push
        # ------------------------------------------------------------
        def na_drawn__log_push(target, world_travel, sloped)
            puts "\n"
            puts '----------------------------------------'
            puts 'DEEP PUSH/PULL APPLIED'
            puts "Target: #{Na__InsertPrimatives.Na__DeepPick__PathLabel(target)}"
            measured =
                if    @na_axis_lock then " along #{NA_DRAWN_AXIS_LABELS[@na_axis_lock]}"
                elsif sloped        then ' along the neighbouring slope'
                else                     ' along the face normal'
                end

            split = @na_pp_split || { :distance => 0.0, :shear => Geom::Vector3d.new(0, 0, 0) }

            puts "Dragged: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(@na_size_d).abs}mm#{measured}"
            puts "Travel: #{Na__InsertPrimatives.Na__DrawnFormat__Mm(world_travel).abs}mm world"
            puts "Local push   : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(split[:distance]).abs}mm (instance scale #{format('%.4f', target[:normal_scale])})"

            if sloped
                route = @na_pp_stretched ? 'stretched (no new geometry, no seam)' : 'pushpull + shear'
                puts "Slope        : #{Na__InsertPrimatives.Na__SlopePush__Label(@na_pp_slope)} — #{route}"
                puts "Sideways     : #{Na__InsertPrimatives.Na__DrawnFormat__Mm(split[:shear].length).abs}mm"
                puts "Seam         : #{@na_pp_seam_healed.to_i} coplanar edge(s) cleared" unless @na_pp_stretched
            end

            puts "Instances affected: #{target[:shared_count]}"
            puts "Grid  : #{Na__InsertPrimatives.Na__DrawnSettings__GridStepLabel}"
            puts "Quads : #{na_drawn__quad_report}"
            puts '----------------------------------------'
        end
        # ---------------------------------------------------------------

        # endregion -------------------------------------------------------------------

    end # End DrawnPushPullTool class

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Quad Ring — Putting the Start Loop Back
    # -----------------------------------------------------------------------------
    #
    # WHAT SKETCHUP DOES AND WHY THE LINE VANISHES:
    # - Pushing a box face outward builds a fresh wall from the start loop to the
    #   finish loop, then MERGES that wall into the coplanar wall it grew out of
    #   and deletes the edge they met on. That deleted edge is the "quad line".
    #   It is not hidden or softened, it is gone, and there is no pushpull flag
    #   that keeps it.
    # - So it is put back: the start loop is re-drawn as edges after the push.
    #   Landing an edge on an existing face splits it — the same merge machinery
    #   that removed the line, run the other way.
    #
    # WHY NOT pushpull(distance, true):
    # - The copy flag ("new starting face") leaves a FACE in the start plane, not
    #   just its edges, and which of the two faces survives flips with the push
    #   direction. Erasing the wrong one opens a hole in the solid. Re-drawing
    #   the loop is direction-agnostic and never removes anything that was there.
    #
    # SELF-CLEANING, BECAUSE THE RING IS NOT ALWAYS WANTED:
    # - Pushing INTO a solid shortens it, so the start loop is left in mid-air.
    #   Rather than special-case the direction, every ring edge that ends up
    #   bounding no face at all is swept back off, which also covers a face that
    #   refused to split. Worst case the push behaves exactly as it does with
    #   quads off — it never leaves debris.
    #
    # -----------------------------------------------------------------------------

    NA_PP_QUAD_TOL = 0.002                                                    # <-- Inches; twice SketchUp's own merge tolerance

    # FUNCTION | Every Loop of a Face, in Definition-Local Points
    # ------------------------------------------------------------
    # Read BEFORE the push: the face is about to move, and these positions are
    # the only record of where it started.
    #
    # CLONED, AND THAT IS THE WHOLE POINT OF THIS FUNCTION:
    # - A record of where something WAS is worthless if it tracks where the
    #   thing goes. Vertex#position must be copied out, not held.
    # - Plain pushpull hid the need for it. It leaves the original vertices
    #   where they are and re-bounds the face on new ones, so a held position
    #   never moved and the ring landed correctly by luck rather than by design.
    # - Slope mode's stretch route moves the face's OWN vertices — that is what
    #   makes it seamless — so a held position followed them. The ring was then
    #   re-drawn on top of the face's new boundary, where add_edges quietly
    #   returned the edges that were already there: four edges "kept", nothing
    #   created, and no line at the joint. That is the quad line that previewed
    #   and never materialised.
    # ------------------------------------------------------------
    def self.Na__PushPull__CaptureLoops(face)
        return [] unless face && face.valid?

        face.loops.map do |loop|
            loop.vertices.map { |vertex| vertex.position.clone }
        end
    rescue StandardError
        []
    end
    # ---------------------------------------------------------------

    # FUNCTION | Re-Draw the Start Loops as Edges After a Push
    # Returns { :kept, :swept, :faces_removed, :misplaced }.
    # ------------------------------------------------------------
    def self.Na__PushPull__StitchQuadRing(entities, loops_local, build_transform)
        stats = { :kept => 0, :swept => 0, :faces_removed => 0, :misplaced => false }
        return stats unless entities && loops_local

        loops_local.each do |points|
            next if points.nil? || points.length < 3

            ring  = points.map { |point| point.transform(build_transform) }
            ring << ring.first                                                # <-- add_edges runs a polyline, it does not close it

            edges = entities.add_edges(ring)
            next if edges.nil? || edges.empty?

            # If the points landed in the wrong coordinate space the edges are
            # real but useless. Take them straight back out and let the plain
            # push stand rather than leaving a stray loop in the model.
            unless Na__InsertPrimatives.Na__PushPull__RingLanded?(edges, points)
                stats[:misplaced] = true
                edges.each { |edge| edge.erase! if edge.valid? }
                next
            end

            stats[:faces_removed] += Na__InsertPrimatives.Na__PushPull__EraseRingFaces(edges, points)

            edges.each do |edge|
                next unless edge.valid?

                if edge.faces.empty?
                    edge.erase!
                    stats[:swept] += 1
                else
                    stats[:kept] += 1
                end
            end
        end

        stats
    end
    # ---------------------------------------------------------------

    # FUNCTION | Did the Ring Land Where It Was Aimed?
    # Vertex positions read back are always definition-local, so they are checked
    # against the local points, never against the transformed ones.
    # ------------------------------------------------------------
    def self.Na__PushPull__RingLanded?(edges, points_local)
        return false if points_local.nil? || points_local.empty?

        # Every start point must show up as an endpoint. More edges than points
        # is normal and fine — a ring segment that runs through an existing
        # vertex comes back split — but a MISSING corner means the ring is not
        # where it was aimed.
        points_local.all? do |wanted|
            edges.any? do |edge|
                edge.valid? &&
                    (edge.start.position.distance(wanted) < NA_PP_QUAD_TOL ||
                     edge.end.position.distance(wanted)   < NA_PP_QUAD_TOL)
            end
        end
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remove the Face a Closed Ring Just Created
    # A closed coplanar loop makes SketchUp fill it in, and that fill is the one
    # thing this mode must not leave behind. Two tests have to pass before
    # anything is erased, and the second one exists because the first alone
    # opens holes in solids:
    #
    # 1. The face's OUTER loop must BE the ring. A surrounding face that merely
    #    shares the ring — the wall around a recess — has a bigger outline and
    #    is left alone.
    # 2. No edge of it may carry exactly two faces. That is the skin test.
    #    Pushing a LOOSE face makes a box, and the box's new bottom sits on the
    #    ring and passes test 1 perfectly — erasing it would leave an
    #    open-bottomed box. On that bottom every edge carries two faces (bottom
    #    plus one side): a manifold pair, so the face is sealing something. An
    #    internal divider carries three (the wall either side of it plus
    #    itself), and an edge left holding nothing but the fill carries one.
    #    Neither of those is sealing anything, so both are safe to cut.
    # ------------------------------------------------------------
    def self.Na__PushPull__EraseRingFaces(edges, points_local)
        removed = 0
        seen    = []

        edges.each do |edge|
            next unless edge.valid?

            edge.faces.each { |face| seen << face unless seen.include?(face) }
        end

        seen.each do |face|
            next unless face.valid?

            outline = face.outer_loop.vertices.map { |vertex| vertex.position }
            next unless Na__InsertPrimatives.Na__PushPull__SameLoop?(outline, points_local)
            next unless Na__InsertPrimatives.Na__PushPull__DividerNotSkin?(face)

            face.erase!
            removed += 1
        end

        removed
    rescue StandardError
        removed
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is This Face Dividing the Solid Rather Than Sealing It?
    # An edge carrying exactly two faces is a manifold pair — this face is one
    # half of the skin there and cutting it would open the solid. Three means
    # the material already meets across that edge without this face's help, and
    # one means the edge is holding nothing else.
    # ------------------------------------------------------------
    def self.Na__PushPull__DividerNotSkin?(face)
        face.edges.none? { |edge| edge.faces.length == 2 }
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Are Two Outlines the Same Loop, Whatever Order They Are In?
    # Compared by distance rather than by a rounded key: a rounded key can
    # straddle its own boundary and call two identical points different, and
    # getting this wrong either leaves the fill face in or erases a real one.
    # ------------------------------------------------------------
    def self.Na__PushPull__SameLoop?(outline, points_local)
        return false unless outline.length == points_local.length

        points_local.all? do |wanted|
            outline.any? { |point| point.distance(wanted) < NA_PP_QUAD_TOL }
        end
    end
    # ---------------------------------------------------------------

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
