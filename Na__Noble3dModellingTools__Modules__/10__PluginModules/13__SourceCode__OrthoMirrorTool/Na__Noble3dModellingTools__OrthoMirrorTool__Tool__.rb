# =============================================================================
# NA NOBLE3D MODELLING TOOLS - ORTHO MIRROR TOOL - TOOL CLASS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__OrthoMirrorTool__Tool__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__OrthoMirrorTool::OrthoMirrorTool
# PURPOSE    : Interactive Sketchup::Tool class for 2D camera-based mirroring
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__OrthoMirrorTool

# -----------------------------------------------------------------------------
# REGION | Tool Class
# -----------------------------------------------------------------------------

        # CLASS | OrthoMirrorTool - Interactive Mirror Placement Tool
        # ------------------------------------------------------------
        class OrthoMirrorTool

            # INITIALIZE | Tool Constructor
            # ------------------------------------------------------------
            def initialize
                @ip             = Sketchup::InputPoint.new               # <-- Create input point for snapping
                @cursor_pos     = nil                                     # <-- Current cursor world position
                @point_type     = :free                                   # <-- Current snap point type
                @state          = STATE_IDLE                              # <-- Tool state machine
                @start_point    = nil                                     # <-- First clicked point
                @end_point      = nil                                     # <-- Second clicked point (preview)
                @selection_copy = nil                                     # <-- Stored selection entities
                @locked_axis    = LOCK_NONE                               # <-- Current axis lock state
                @key_held       = {                                       # <-- Tracks held arrow keys (defeats OS auto-repeat)
                    VK_RIGHT => false,
                    VK_LEFT  => false,
                    VK_UP    => false,
                    VK_DOWN  => false
                }
            end
            # ------------------------------------------------------------


            # ACTIVATE | Called when tool is activated
            # ------------------------------------------------------------
            def activate
                model = Sketchup.active_model
                view  = model.active_view

                puts "\n"
                puts "----------------------------------------"
                puts "ORTHO MIRROR TOOL ACTIVATED"
                puts "Arrow keys: Right=Red(X), Left=Green(Y), Up=Blue(Z)"

                unless Na__OrthoMirrorTool.is_parallel_projection?(view)
                    puts "WARNING: Not in Parallel Projection mode"
                    puts "Tool works best in Top/Front/Right etc views"
                end

                if model.selection.empty?
                    puts "WARNING: No objects selected"
                    puts "Please select objects to mirror first"
                    Sketchup::set_status_text("Select objects first, then reactivate tool", SB_PROMPT)
                else
                    puts "Selection count: #{model.selection.count}"
                    puts "Click first point of mirror axis"
                    Sketchup::set_status_text("Click first point of mirror axis. Arrow keys to lock axis.", SB_PROMPT)
                end

                ortho_view = Na__OrthoMirrorTool.identify_ortho_view(view)
                puts "Current view: #{ortho_view.to_s.upcase}"
                puts "----------------------------------------"

                @state       = STATE_IDLE
                @start_point = nil
                @locked_axis = LOCK_NONE
                view.invalidate
            end
            # ------------------------------------------------------------


            # DEACTIVATE | Called when tool is deselected
            # ------------------------------------------------------------
            def deactivate(view)
                view.lock_inference                                       # <-- Unlock any inference lock
                view.invalidate
                @state       = STATE_IDLE
                @start_point = nil
                @locked_axis = LOCK_NONE
            end
            # ------------------------------------------------------------


            # RESUME | Called when tool is resumed
            # ------------------------------------------------------------
            def resume(view)
                view.invalidate
                update_status_text
            end
            # ------------------------------------------------------------


            # ON MOUSE MOVE | Track cursor position and snap type
            # ------------------------------------------------------------
            def onMouseMove(flags, x, y, view)
                @ip.pick(view, x, y)
                @cursor_pos = @ip.position
                @point_type = Na__OrthoMirrorTool.detect_point_type(@ip)

                if @state == STATE_FIRST_POINT_SET && @cursor_pos
                    @end_point = get_constrained_end_point(@cursor_pos)
                end

                view.invalidate
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Get Constrained End Point Based on Axis Lock
            # ------------------------------------------------------------
            def get_constrained_end_point(raw_position)
                return raw_position unless @start_point
                return raw_position if @locked_axis == LOCK_NONE

                axis_vector = world_axis_vector_for(@locked_axis)
                return raw_position unless axis_vector

                Na__OrthoMirrorTool.constrain_point_to_axis(@start_point, raw_position, axis_vector)
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Resolve Locked Axis to World Direction (Context Aware)
            # ------------------------------------------------------------
            # Single source of truth for the locked axis direction. Uses the active
            # model's edit_transform so the lock follows the current group/component.
            # ------------------------------------------------------------
            def world_axis_vector_for(lock_state)
                model          = Sketchup.active_model
                edit_transform = model ? model.edit_transform : nil
                Na__OrthoMirrorTool.world_axis_for_lock(lock_state, edit_transform)
            end
            # ------------------------------------------------------------


            # ON LEFT BUTTON DOWN | Handle click events
            # ------------------------------------------------------------
            def onLButtonDown(flags, x, y, view)
                @ip.pick(view, x, y)
                return unless @ip.valid?

                click_pos = @ip.position

                case @state
                when STATE_IDLE
                    handle_first_click(click_pos, view)
                when STATE_FIRST_POINT_SET
                    handle_second_click(click_pos, view)
                end
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Handle First Point Click
            # ------------------------------------------------------------
            def handle_first_click(position, view)
                model = Sketchup.active_model

                if model.selection.empty?
                    UI.beep
                    Sketchup::set_status_text("No selection! Select objects first", SB_PROMPT)
                    return
                end

                @start_point = position
                @state       = STATE_FIRST_POINT_SET

                apply_inference_lock(view)                                # <-- Engage inference if pre-locked

                puts "First point set: #{format_point(@start_point)}"
                update_status_text
                view.invalidate
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Handle Second Point Click
            # ------------------------------------------------------------
            def handle_second_click(position, view)
                @end_point = get_constrained_end_point(position)

                if @start_point.distance(@end_point) < 0.001
                    UI.beep
                    Sketchup::set_status_text("Points too close! Click different point", SB_PROMPT)
                    return
                end

                puts "Second point set: #{format_point(@end_point)}"
                puts "Axis lock: #{Na__OrthoMirrorTool.get_axis_name(@locked_axis)}" if @locked_axis != LOCK_NONE

                execute_mirror_transformation(view)

                @state       = STATE_IDLE
                @start_point = nil
                @end_point   = nil
                @locked_axis = LOCK_NONE
                view.lock_inference

                Sketchup::set_status_text("Mirror complete. Click for new mirror axis", SB_PROMPT)
                view.invalidate
            end
            # ------------------------------------------------------------


            # ON KEY DOWN | Handle keyboard input
            # ------------------------------------------------------------
            def onKeyDown(key, repeat, flags, view)
                escape_key_code = (Sketchup.platform == :platform_win ? 27 : 53)
                return handle_escape(view) if key == escape_key_code

                if @key_held.key?(key)
                    return true if @key_held[key]                        # <-- Swallow OS auto-repeat
                    @key_held[key] = true
                    handle_arrow_key(key, view)
                    return true
                end

                false
            end
            # ------------------------------------------------------------


            # ON KEY UP | Release Arrow Key Hold State
            # ------------------------------------------------------------
            def onKeyUp(key, repeat, flags, view)
                @key_held[key] = false if @key_held.key?(key)
                false
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Route Arrow Key to Axis Lock Action
            # ------------------------------------------------------------
            def handle_arrow_key(key, view)
                case key
                when VK_RIGHT then handle_axis_lock_key(LOCK_X, view)
                when VK_LEFT  then handle_axis_lock_key(LOCK_Y, view)
                when VK_UP    then handle_axis_lock_key(LOCK_Z, view)
                when VK_DOWN  then unlock_axis(view)
                end
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Handle Escape Key (Cancel Current Step)
            # ------------------------------------------------------------
            def handle_escape(view)
                return false unless @state == STATE_FIRST_POINT_SET      # <-- Idle: let SketchUp exit the tool

                @state       = STATE_IDLE
                @start_point = nil
                @end_point   = nil
                @locked_axis = LOCK_NONE
                view.lock_inference
                Sketchup::set_status_text("Cancelled. Click first point of mirror axis", SB_PROMPT)
                view.invalidate
                true
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Handle Axis Lock Key Press
            # ------------------------------------------------------------
            def handle_axis_lock_key(new_lock, view)
                if @locked_axis == new_lock
                    unlock_axis(view)                                     # <-- Toggle off
                else
                    lock_to_axis(new_lock, view)
                end
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Lock to Specified Axis
            # ------------------------------------------------------------
            def lock_to_axis(axis_lock, view)
                axis_name      = Na__OrthoMirrorTool.get_axis_name(axis_lock)
                world_axis     = world_axis_vector_for(axis_lock)
                view_direction = Na__OrthoMirrorTool.get_camera_view_direction(view)

                if world_axis && world_axis.parallel?(view_direction)
                    UI.beep
                    Sketchup::set_status_text("Cannot lock #{axis_name} - it points into the screen here. Try another arrow.", SB_PROMPT)
                    return
                end

                @locked_axis = axis_lock
                apply_inference_lock(view)

                puts "Axis locked to: #{axis_name}"
                update_status_text
                view.invalidate
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Engage Native Inference Lock Along the Locked Axis
            # ------------------------------------------------------------
            # Keeps SketchUp's own inference engine aligned with the manual axis
            # projection (single shared axis direction) so the cursor snaps and the
            # VCB length read-out feel native. Only meaningful once an anchor exists.
            # ------------------------------------------------------------
            def apply_inference_lock(view)
                return unless @start_point
                return if @locked_axis == LOCK_NONE

                axis_vector = world_axis_vector_for(@locked_axis)
                return unless axis_vector

                ip1 = Sketchup::InputPoint.new(@start_point)
                ip2 = Sketchup::InputPoint.new(@start_point.offset(axis_vector, 1000.mm))
                view.lock_inference(ip1, ip2)
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Unlock Axis Constraint
            # ------------------------------------------------------------
            def unlock_axis(view)
                @locked_axis = LOCK_NONE
                view.lock_inference

                puts "Axis lock released"
                Sketchup::set_status_text("Axis unlocked. Click second point or use arrow keys to lock.", SB_PROMPT)
                view.invalidate
            end
            # ------------------------------------------------------------


            # ON CANCEL | Handle tool cancellation
            # ------------------------------------------------------------
            def onCancel(reason, view)
                @state       = STATE_IDLE
                @start_point = nil
                @locked_axis = LOCK_NONE
                view.lock_inference
                view.invalidate
            end
            # ------------------------------------------------------------


            # DRAW | Render Visual Feedback Overlays
            # ------------------------------------------------------------
            def draw(view)
                return unless @cursor_pos

                @ip.draw(view)

                if @state == STATE_FIRST_POINT_SET && @start_point
                    preview_end = get_constrained_end_point(@cursor_pos)
                    draw_preview_line(view, @start_point, preview_end)
                    draw_axis_lock_indicator(view) if @locked_axis != LOCK_NONE
                end

                case @point_type
                when :vertex   then draw_endpoint_indicator(view, @cursor_pos)
                when :midpoint then draw_midpoint_indicator(view, @cursor_pos)
                end

                draw_start_point_marker(view, @start_point) if @start_point
            end
            # ------------------------------------------------------------


            # GET EXTENTS | Report Overlay Bounds So Drawing Is Not Clipped
            # ------------------------------------------------------------
            # SketchUp clips tool drawing to the returned bounding box. Without this,
            # the preview line and the long dashed axis guide can vanish at certain
            # zoom levels. Include every point the tool draws.
            # ------------------------------------------------------------
            def getExtents
                bounds = Geom::BoundingBox.new
                bounds.add(@start_point) if @start_point
                bounds.add(@end_point)   if @end_point
                bounds.add(@cursor_pos)  if @cursor_pos

                if @start_point && @locked_axis != LOCK_NONE
                    axis_vector = world_axis_vector_for(@locked_axis)
                    if axis_vector
                        bounds.add(@start_point.offset(axis_vector, 2000.mm))
                        bounds.add(@start_point.offset(axis_vector.reverse, 2000.mm))
                    end
                end

                bounds
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Draw Axis Lock Indicator
            # ------------------------------------------------------------
            def draw_axis_lock_indicator(view)
                return unless @start_point && @locked_axis != LOCK_NONE

                axis_vector = world_axis_vector_for(@locked_axis)
                axis_color  = Na__OrthoMirrorTool.get_axis_color(@locked_axis)
                return unless axis_vector

                extend_length = 2000.mm
                pt_pos = @start_point.offset(axis_vector, extend_length)
                pt_neg = @start_point.offset(axis_vector.reverse, extend_length)

                view.line_stipple  = "."
                view.line_width    = 1
                view.drawing_color = axis_color
                view.draw_line(pt_neg, pt_pos)
                view.line_stipple  = ""
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Draw Preview Line Between Points
            # ------------------------------------------------------------
            def draw_preview_line(view, pt1, pt2)
                view.line_stipple  = ""
                view.line_width    = PREVIEW_LINE_WIDTH
                view.drawing_color = Na__OrthoMirrorTool.get_axis_color(@locked_axis)
                view.draw_line(pt1, pt2)
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Draw Start Point Marker
            # ------------------------------------------------------------
            def draw_start_point_marker(view, point)
                screen_pt    = view.screen_coords(point)
                size         = INDICATOR_SIZE
                marker_color = Na__OrthoMirrorTool.get_axis_color(@locked_axis)
                view.drawing_color = marker_color

                x    = screen_pt.x
                y    = screen_pt.y
                half = size / 2.0

                square_pts = [
                    Geom::Point3d.new(x - half, y - half, 0),
                    Geom::Point3d.new(x + half, y - half, 0),
                    Geom::Point3d.new(x + half, y + half, 0),
                    Geom::Point3d.new(x - half, y + half, 0)
                ]

                view.draw2d(GL_QUADS, square_pts)
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Draw Endpoint Indicator (Red Square)
            # ------------------------------------------------------------
            def draw_endpoint_indicator(view, point)
                screen_pt = view.screen_coords(point)
                size      = INDICATOR_SIZE

                view.drawing_color = ENDPOINT_COLOR
                view.line_width    = 2

                x    = screen_pt.x
                y    = screen_pt.y
                half = size / 2.0

                square_pts = [
                    Geom::Point3d.new(x - half, y - half, 0),
                    Geom::Point3d.new(x + half, y - half, 0),
                    Geom::Point3d.new(x + half, y + half, 0),
                    Geom::Point3d.new(x - half, y + half, 0)
                ]

                view.draw2d(GL_LINE_LOOP, square_pts)
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Draw Midpoint Indicator (Green Circle)
            # ------------------------------------------------------------
            def draw_midpoint_indicator(view, point)
                screen_pt = view.screen_coords(point)
                radius    = INDICATOR_SIZE / 2.0

                view.drawing_color = MIDPOINT_COLOR
                view.line_width    = 2

                x        = screen_pt.x
                y        = screen_pt.y
                segments = 12

                circle_pts = (0...segments).map do |i|
                    angle = (2.0 * Math::PI * i) / segments
                    Geom::Point3d.new(x + radius * Math.cos(angle), y + radius * Math.sin(angle), 0)
                end

                view.draw2d(GL_LINE_LOOP, circle_pts)
            end
            # ------------------------------------------------------------


            # FUNCTION | Execute Mirror Transformation
            # ------------------------------------------------------------
            def execute_mirror_transformation(view)
                model     = Sketchup.active_model
                selection = model.selection
                entities  = model.active_entities

                if selection.empty?
                    UI.beep
                    puts "ERROR: No entities selected to mirror"
                    return
                end

                # Resolve the active edit-context transform so the mirror is BUILT and
                # APPLIED in the same (local) space as the geometry being copied. At the
                # model root this is identity; inside a group/component it is that
                # context's local->world transform.
                edit_transform = model.edit_transform
                inverse_edit   = edit_transform.inverse

                local_start = @start_point.transform(inverse_edit)
                local_end   = @end_point.transform(inverse_edit)

                world_view_direction = Na__OrthoMirrorTool.get_camera_view_direction(view)
                local_view_direction = world_view_direction.transform(inverse_edit)

                plane_normal = Na__OrthoMirrorTool.calculate_mirror_plane_normal(
                    local_start, local_end, local_view_direction
                )

                if plane_normal.nil?
                    UI.beep
                    Sketchup::set_status_text("Mirror axis points into the screen - pick a different axis or view.", SB_PROMPT)
                    puts "ERROR: Could not calculate mirror plane (axis parallel to view direction)"
                    return
                end

                midpoint         = Geom::Point3d.linear_combination(0.5, local_start, 0.5, local_end)
                mirror_transform = Na__OrthoMirrorTool.build_mirror_transform(midpoint, plane_normal)

                model.start_operation('Mirror Selection', true)

                begin
                    source_group  = entities.add_group(selection.to_a)
                    mirrored_copy = entities.add_instance(source_group.definition, source_group.transformation)
                    mirrored_copy.transform!(mirror_transform)
                    source_group.explode

                    mirrored_count = finalize_mirror_result(selection, mirrored_copy)

                    model.commit_operation

                    puts "\n"
                    puts "----------------------------------------"
                    puts "MIRROR OPERATION COMPLETE"
                    puts "Context: #{edit_transform.identity? ? 'Model root' : 'Inside group/component'}"
                    puts "Mirror axis: #{format_point(@start_point)} to #{format_point(@end_point)}"
                    puts "Plane normal (local): [#{plane_normal.x.round(3)}, #{plane_normal.y.round(3)}, #{plane_normal.z.round(3)}]"
                    puts "Mirrored entities: #{mirrored_count}"
                    puts "----------------------------------------"

                rescue => error
                    model.abort_operation
                    puts "ERROR: Mirror operation failed - #{error.message}"
                    UI.beep
                end
            end
            # ------------------------------------------------------------


            # SUB FUNCTION | Dispose Mirror Result and Update Selection
            # ------------------------------------------------------------
            # Leaves the mirrored copy as a tidy group (default, non-destructive) or
            # explodes it into the current context. Selects the result and returns the
            # number of resulting entities for logging.
            # ------------------------------------------------------------
            def finalize_mirror_result(selection, mirrored_copy)
                selection.clear

                unless MIRROR_RESULT_AS_GROUP
                    exploded = mirrored_copy.explode
                    kept     = exploded ? exploded.grep(Sketchup::Drawingelement) : []
                    selection.add(kept) unless kept.empty?
                    return kept.length
                end

                selection.add(mirrored_copy)
                mirrored_copy.definition.entities.count
            end
            # ------------------------------------------------------------


            # HELPER FUNCTION | Format Point for Console Output
            # ------------------------------------------------------------
            def format_point(pt)
                return "nil" unless pt
                "[#{pt.x.to_mm.round(1)}mm, #{pt.y.to_mm.round(1)}mm, #{pt.z.to_mm.round(1)}mm]"
            end
            # ------------------------------------------------------------


            # HELPER FUNCTION | Update Status Bar Text
            # ------------------------------------------------------------
            def update_status_text
                case @state
                when STATE_IDLE
                    if @locked_axis != LOCK_NONE
                        axis_name = Na__OrthoMirrorTool.get_axis_name(@locked_axis)
                        Sketchup::set_status_text("#{axis_name} armed. Click first point of mirror axis. Down arrow to unlock.", SB_PROMPT)
                    else
                        Sketchup::set_status_text("Click first point of mirror axis. Arrow keys: Right=X, Left=Y, Up=Z.", SB_PROMPT)
                    end
                when STATE_FIRST_POINT_SET
                    if @locked_axis != LOCK_NONE
                        axis_name = Na__OrthoMirrorTool.get_axis_name(@locked_axis)
                        Sketchup::set_status_text("Locked to #{axis_name}. Click second point. Down arrow to unlock.", SB_PROMPT)
                    else
                        Sketchup::set_status_text("Click second point. Arrow keys: Right=X, Left=Y, Up=Z.", SB_PROMPT)
                    end
                end
            end
            # ------------------------------------------------------------

        end # class OrthoMirrorTool

# endregion -------------------------------------------------------------------

    end # module Na__OrthoMirrorTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
