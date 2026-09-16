# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - HEDGE TOOL
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__HedgeTool__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__HedgeTool
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Draw a connected mitered hedge path, then create it in one undo
# CREATED    : 2026
#
# SketchUp 2026 routes Enter without VCB text to onReturn. Handling raw Enter
# in onKeyDown would consume a typed length before onUserText.
# Viewport mesh refreshes are limited to ten per second while moving.
#
# =============================================================================

require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Tool__'

module Na__Noble3dModellingTools

    class Na__VegetationSketcher__HedgeTool < Na__VegetationSketcher__PlacementTool

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PREVIEW_INTERVAL = 0.1

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Construction and Lifecycle
# -----------------------------------------------------------------------------

        def initialize(options, owner)
            super(options.merge('path' => nil), owner)
            @na_waypoints = []
            @na_held_keys = {}
            @na_typing = false
        end

        def deactivate(view)
            na_cancel_preview_refresh
            view.lock_inference
            super
        end

        def suspend(view)
            na_cancel_preview_refresh
            super
        end

        def resume(view)
            @na_held_keys.clear
            @na_typing = false
            super
            na_reanchor(view)
        end

        def na_update_options(options)
            @na_options = options.merge('path' => nil)
            @na_mesh_key = nil
            na_refresh_preview(force: true)
            na_status
            @na_model.active_view.invalidate
        end

        def na_status
            prompt = @na_waypoints.empty? ? 'Click or drag to begin a hedge.' : "#{@na_waypoints.length - 1} runs: click the next corner. Enter / double-click / right-click / Finish creates the hedge."
            lock = @na_axis ? " Locked: #{@na_axis == :x ? 'RED' : @na_axis == :y ? 'GREEN' : 'PREVIOUS RUN'}." : ''
            Sketchup.status_text = prompt + ' Right: red. Left: green. Down: previous run. Up: unlock. Backspace: undo point. Esc: cancel.' + lock
            Sketchup.set_status_text('Next run', SB_VCB_LABEL)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Axis Lock and Picking
# -----------------------------------------------------------------------------

        def na_axis_vector
            case @na_axis
            when :x then Geom::Vector3d.new(1, 0, 0)
            when :y then Geom::Vector3d.new(0, 1, 0)
            when :parallel
                @na_waypoints.length > 1 ? (@na_waypoints[-1] - @na_waypoints[-2]).normalize : Geom::Vector3d.new(1, 0, 0)
            end
        end

        def na_reanchor(view)
            @na_anchor = @na_waypoints.last
            @na_anchor_input = Sketchup::InputPoint.new(@na_anchor) if @na_anchor
            view.lock_inference
            direction = na_axis_vector
            if @na_anchor && direction
                view.lock_inference(Sketchup::InputPoint.new(@na_anchor), Sketchup::InputPoint.new(@na_anchor.offset(direction, 1)))
            end
            na_status
        end

        def na_pick(x, y, view, force: false)
            return unless na_valid_context?

            @na_last_xy = [x, y]
            @na_anchor ? @na_input.pick(view, x, y, @na_anchor_input) : @na_input.pick(view, x, y)
            raw = @na_input.valid? ? @na_input.position : Geom.intersect_line_plane(view.pickray(x, y), [@na_anchor || ORIGIN, Z_AXIS])
            return unless raw

            @na_cursor = Geom::Point3d.new(raw.x, raw.y, @na_anchor ? @na_anchor.z : raw.z)
            direction = na_axis_vector
            @na_cursor = @na_anchor.offset(direction, (@na_cursor - @na_anchor).dot(direction)) if @na_anchor && direction
            view.tooltip = @na_input.valid? ? @na_input.tooltip : ''
            Sketchup.set_status_text(Sketchup.format_length(@na_anchor.distance(@na_cursor)), SB_VCB_VALUE) if @na_anchor
            na_refresh_preview(force: force)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Editing
# -----------------------------------------------------------------------------

        def na_local_path(points)
            origin = points.first
            points.map { |p| [(p.x - origin.x) * 25.4, (p.y - origin.y) * 25.4, 0.0] }
        end

        def na_options_for(points)
            Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Resolve(@na_options.merge('path' => na_local_path(points)))
        end

        def na_append_cursor(view)
            return false unless @na_cursor && @na_anchor && @na_cursor.distance(@na_anchor) >= 50.mm

            candidate = @na_waypoints + [@na_cursor.clone]
            options = na_options_for(candidate)
            Na__VegetationSketcher__HedgePath.Na__VegetationSketcher__HedgePath__Prepare(options['path'], options['width'])
            @na_waypoints = candidate
            na_reanchor(view)
            na_refresh_preview(force: true)
            @na_owner.na_tool_progress(options['length'], "#{@na_waypoints.length - 1} runs set - click another corner or Finish")
            true
        end

        def na_finish_path
            return false if @na_waypoints.length < 2
            raise ArgumentError, 'The editing context changed. Start drawing again.' unless na_valid_context?

            options = na_options_for(@na_waypoints)
            transform = Geom::Transformation.translation(@na_waypoints.first.to_a)
            entity = Na__VegetationSketcher__Builder.Na__VegetationSketcher__Builder__Create(@na_model, options, transform)
            @na_owner.na_created(entity)
            @na_waypoints.clear
            @na_anchor = nil
            @na_model.active_view.lock_inference
            entity
        end

        def na_finish_and_exit(view)
            na_finish_path
            @na_model.select_tool(nil)
            view.invalidate
        rescue StandardError => error
            @na_owner.na_report(error.message, 'error')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Pointer, Keyboard and VCB
# -----------------------------------------------------------------------------

        def onLButtonDown(_flags, x, y, view)
            return unless na_valid_context?

            @na_typing = false
            na_pick(x, y, view, force: true)
            return unless @na_cursor

            @na_down = [x, y]
            @na_began_here = @na_waypoints.empty?
            if @na_began_here
                @na_waypoints << @na_cursor.clone
                na_reanchor(view)
            end
            view.invalidate
        rescue StandardError => error
            @na_owner.na_report(error.message, 'error')
        end

        def onLButtonUp(_flags, x, y, view)
            return unless @na_down && na_valid_context?

            na_pick(x, y, view, force: true)
            dragged = Math.hypot(x - @na_down[0], y - @na_down[1]) > 5
            na_append_cursor(view) if !@na_began_here || dragged
            @na_down = nil
            view.invalidate
        rescue StandardError => error
            @na_down = nil
            @na_owner.na_report(error.message, 'error')
        end

        def onReturn(view)
            na_finish_and_exit(view)
        end

        def onRButtonDown(_flags, _x, _y, view)
            na_finish_and_exit(view)
        end

        def getMenu(_menu, *_args)
        end

        def onLButtonDoubleClick(_flags, x, y, view)
            na_pick(x, y, view, force: true)
            na_append_cursor(view)
            na_finish_and_exit(view)
        rescue StandardError => error
            @na_owner.na_report(error.message, 'error')
        end

        def onKeyDown(key, _repeat, _flags, view)
            if (48..57).cover?(key) || (96..111).cover?(key) || [187, 188, 189, 190].include?(key)
                @na_typing = true
                return false
            end
            return false if [8, 46].include?(key) && @na_typing
            return true if @na_held_keys[key]

            case key
            when 39, 37, 40, 38
                requested = { 39 => :x, 37 => :y, 40 => :parallel, 38 => nil }[key]
                @na_axis = @na_axis == requested ? nil : requested
                @na_held_keys[key] = true
                na_reanchor(view)
                na_pick(*@na_last_xy, view, force: true) if @na_last_xy
            when 8, 46
                @na_held_keys[key] = true
                @na_waypoints.pop
                @na_mesh_key = nil
                na_reanchor(view)
                na_refresh_preview(force: true)
            when 82
                @na_held_keys[key] = true
                @na_owner.na_new_variation
            else
                return false
            end
            view.invalidate
            true
        rescue StandardError => error
            @na_owner.na_report(error.message, 'error')
            true
        end

        def onKeyUp(key, _repeat, _flags, _view)
            @na_held_keys.delete(key)
            false
        end

        def onUserText(text, view)
            @na_typing = false
            return unless @na_anchor

            length = Sketchup.parse_length(text)
            raise ArgumentError, 'Enter a run length from 50 mm to 100 m, for example 3m.' unless length && length >= 50.mm && length <= 100000.mm

            direction = na_axis_vector || (@na_cursor && @na_cursor - @na_anchor)
            direction = Geom::Vector3d.new(1, 0, 0) unless direction && direction.length > 0.001
            direction.reverse! if na_axis_vector && @na_cursor && (@na_cursor - @na_anchor).dot(direction) < 0
            @na_cursor = @na_anchor.offset(direction, length)
            na_append_cursor(view)
            view.invalidate
        rescue StandardError => error
            @na_owner.na_report(error.message, 'error')
        end

        def onCancel(_reason, view)
            na_cancel_preview_refresh
            @na_typing = false
            if @na_waypoints.empty?
                @na_model.select_tool(nil)
            else
                @na_waypoints.clear
                @na_anchor = @na_mesh_key = @na_triangles = @na_lines = @na_preview_points = @na_preview_data = nil
                @na_axis = nil
                na_reanchor(view)
                @na_owner.na_preview if @na_owner.respond_to?(:na_preview)
                @na_owner.na_tool_progress(nil, 'Path cancelled - click to start again')
            end
            view.invalidate
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Preview Mesh and Draw
# -----------------------------------------------------------------------------

        def na_refresh_preview(force: false)
            points = @na_waypoints.dup
            points << @na_cursor if @na_cursor && !points.empty? && @na_cursor.distance(points.last) >= 50.mm
            if points.length < 2
                na_cancel_preview_refresh
                @na_preview_points = @na_triangles = @na_lines = @na_preview_data = nil
                return
            end
            return if na_throttle_preview(force)

            na_cancel_preview_refresh
            @na_preview_stamp = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            options = na_options_for(points)
            key = [options, points.first.to_a]
            return if @na_mesh_key == key

            data = Na__VegetationSketcher__Mesh.Na__VegetationSketcher__Mesh__Build(options, preview: :viewport)
            @na_preview_data = data
            transform = Geom::Transformation.translation(points.first.to_a)
            @na_preview_points = data[:points].map { |p| Geom::Point3d.new(p.map { |n| n / 25.4 }).transform(transform) }
            @na_triangles = data[:quads].flat_map { |a, b, c, d| [a, b, c, a, c, d].map { |i| @na_preview_points[i] } }
            stride = [(data[:quads].size / 900.0).ceil, 1].max
            @na_lines = data[:quads].each_slice(stride).flat_map { |slice| q = slice.first; [q[0], q[1], q[1], q[2]].map { |i| @na_preview_points[i] } }
            @na_mesh_key, @na_preview_error = key, nil
            Sketchup.set_status_text(Sketchup.format_length(@na_anchor.distance(@na_cursor)), SB_VCB_VALUE) if @na_anchor && @na_cursor
            @na_owner.na_tool_progress(options['length'], "#{@na_waypoints.length - 1} runs set - click next corner or Finish", data[:requested_quads])
            @na_owner.na_tool_preview(data)
        rescue ArgumentError => error
            if @na_preview_error != error.message
                @na_owner.na_tool_progress(nil, error.message)
                @na_preview_error = error.message
            end
        end

        def na_throttle_preview(force)
            stamp = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return false if force || !@na_preview_stamp || stamp - @na_preview_stamp >= NA_PREVIEW_INTERVAL

            unless @na_refresh_timer
                @na_refresh_timer = UI.start_timer(NA_PREVIEW_INTERVAL - (stamp - @na_preview_stamp), false) do
                    @na_refresh_timer = nil
                    if na_active? && !@na_suspended && na_valid_context?
                        na_refresh_preview(force: true)
                        @na_model.active_view.invalidate
                    end
                end
            end
            true
        end

        def na_cancel_preview_refresh
            UI.stop_timer(@na_refresh_timer) if @na_refresh_timer
            @na_refresh_timer = nil
        end

        def draw(view)
            super
            return if @na_suspended || !na_valid_context?

            view.drawing_color = 'DodgerBlue'
            view.line_width = 2
            view.draw(GL_LINE_STRIP, @na_waypoints) if @na_waypoints.length > 1
            view.draw_points(@na_waypoints, 6, 1, 'DodgerBlue') unless @na_waypoints.empty?
            if @na_preview_error && @na_anchor && @na_cursor
                view.drawing_color = 'red'
                view.draw(GL_LINES, [@na_anchor, @na_cursor])
            end
        end

# endregion -------------------------------------------------------------------

    end # class Na__VegetationSketcher__HedgeTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
