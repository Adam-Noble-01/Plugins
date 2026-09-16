# frozen_string_literal: true

require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Tool__'

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    class HedgeTool < PlacementTool
      PREVIEW_INTERVAL = 0.1
      attr_reader :preview_data
      def initialize(options, owner)
        super(options.merge('path' => nil), owner)
        @waypoints = []
        @held_keys = {}
        @typing = false
      end

      def status
        prompt = @waypoints.empty? ? 'Click or drag to begin a hedge.' : "#{@waypoints.length - 1} runs: click the next corner. Enter / double-click / right-click / Finish creates the hedge."
        lock = @axis ? " Locked: #{@axis == :x ? 'RED' : @axis == :y ? 'GREEN' : 'PREVIOUS RUN'}." : ''
        Sketchup.status_text = prompt + ' Right: red. Left: green. Down: previous run. Up: unlock. Backspace: undo point. Esc: cancel.' + lock
        Sketchup.set_status_text('Next run', SB_VCB_LABEL)
      end

      def deactivate(view)
        cancel_preview_refresh
        view.lock_inference
        super
      end

      def suspend(view)
        cancel_preview_refresh
        super
      end

      def resume(view)
        @held_keys.clear
        @typing = false
        super
        reanchor(view)
      end

      def update_options(options)
        @options = options.merge('path' => nil)
        @mesh_key = nil
        refresh_preview(force: true)
        status
        @model.active_view.invalidate
      end

      def axis_vector
        case @axis
        when :x then Geom::Vector3d.new(1, 0, 0)
        when :y then Geom::Vector3d.new(0, 1, 0)
        when :parallel
          @waypoints.length > 1 ? (@waypoints[-1] - @waypoints[-2]).normalize : Geom::Vector3d.new(1, 0, 0)
        end
      end

      def reanchor(view)
        @anchor = @waypoints.last
        @anchor_input = Sketchup::InputPoint.new(@anchor) if @anchor
        view.lock_inference
        direction = axis_vector
        if @anchor && direction
          view.lock_inference(Sketchup::InputPoint.new(@anchor), Sketchup::InputPoint.new(@anchor.offset(direction, 1)))
        end
        status
      end

      def pick(x, y, view, force: false)
        return unless valid_context?
        @last_xy = [x, y]
        @anchor ? @input.pick(view, x, y, @anchor_input) : @input.pick(view, x, y)
        raw = @input.valid? ? @input.position : Geom.intersect_line_plane(view.pickray(x, y), [@anchor || ORIGIN, Z_AXIS])
        return unless raw
        @cursor = Geom::Point3d.new(raw.x, raw.y, @anchor ? @anchor.z : raw.z)
        direction = axis_vector
        @cursor = @anchor.offset(direction, (@cursor - @anchor).dot(direction)) if @anchor && direction
        view.tooltip = @input.valid? ? @input.tooltip : ''
        Sketchup.set_status_text(Sketchup.format_length(@anchor.distance(@cursor)), SB_VCB_VALUE) if @anchor
        refresh_preview(force: force)
      end

      def onLButtonDown(_flags, x, y, view)
        return unless valid_context?
        @typing = false
        pick(x, y, view, force: true)
        return unless @cursor
        @down = [x, y]
        @began_here = @waypoints.empty?
        if @began_here
          @waypoints << @cursor.clone
          reanchor(view)
        end
        view.invalidate
      rescue StandardError => e
        @owner.report(e.message, 'error')
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @down && valid_context?
        pick(x, y, view, force: true)
        dragged = Math.hypot(x - @down[0], y - @down[1]) > 5
        append_cursor(view) if !@began_here || dragged
        @down = nil
        view.invalidate
      rescue StandardError => e
        @down = nil
        @owner.report(e.message, 'error')
      end

      def local_path(points)
        origin = points.first
        points.map { |p| [(p.x - origin.x) * 25.4, (p.y - origin.y) * 25.4, 0.0] }
      end

      def options_for(points)
        Options.resolve(@options.merge('path' => local_path(points)))
      end

      def append_cursor(view)
        return false unless @cursor && @anchor && @cursor.distance(@anchor) >= 50.mm
        candidate = @waypoints + [@cursor.clone]
        options = options_for(candidate)
        HedgePath.prepare(options['path'], options['width'])
        @waypoints = candidate
        reanchor(view)
        refresh_preview(force: true)
        @owner.tool_progress(options['length'], "#{@waypoints.length - 1} runs set - click another corner or Finish")
        true
      end

      def finish_path
        return false if @waypoints.length < 2
        raise ArgumentError, 'The editing context changed. Start drawing again.' unless valid_context?
        options = options_for(@waypoints)
        transform = Geom::Transformation.translation(@waypoints.first.to_a)
        entity = Builder.create(@model, options, transform)
        @owner.created(entity)
        @waypoints.clear
        @anchor = nil
        @model.active_view.lock_inference
        entity
      end

      def finish_and_exit(view)
        finish_path
        @model.select_tool(nil)
        view.invalidate
      rescue StandardError => e
        @owner.report(e.message, 'error')
      end

      # SketchUp 2026 routes Enter without VCB text to onReturn. Handling raw
      # Enter in onKeyDown would consume a typed length before onUserText.
      def onReturn(view); finish_and_exit(view); end
      def onRButtonDown(_flags, _x, _y, view); finish_and_exit(view); end
      def getMenu(_menu, *_args); end

      def onLButtonDoubleClick(_flags, x, y, view)
        pick(x, y, view, force: true)
        append_cursor(view)
        finish_and_exit(view)
      rescue StandardError => e
        @owner.report(e.message, 'error')
      end

      def onKeyDown(key, _repeat, _flags, view)
        if (48..57).cover?(key) || (96..111).cover?(key) || [187, 188, 189, 190].include?(key)
          @typing = true
          return false
        end
        return false if [8, 46].include?(key) && @typing
        return true if @held_keys[key]
        case key
        when 39, 37, 40, 38
          requested = { 39 => :x, 37 => :y, 40 => :parallel, 38 => nil }[key]
          @axis = @axis == requested ? nil : requested
          @held_keys[key] = true
          reanchor(view)
          pick(*@last_xy, view, force: true) if @last_xy
        when 8, 46
          @held_keys[key] = true
          @waypoints.pop
          @mesh_key = nil
          reanchor(view)
          refresh_preview(force: true)
        when 82
          @held_keys[key] = true
          @owner.new_variation
        else
          return false
        end
        view.invalidate
        true
      rescue StandardError => e
        @owner.report(e.message, 'error')
        true
      end

      def onKeyUp(key, _repeat, _flags, _view)
        @held_keys.delete(key)
        false
      end

      def onUserText(text, view)
        @typing = false
        return unless @anchor
        length = Sketchup.parse_length(text)
        raise ArgumentError, 'Enter a run length from 50 mm to 100 m, for example 3m.' unless length && length >= 50.mm && length <= 100000.mm
        direction = axis_vector || (@cursor && @cursor - @anchor)
        direction = Geom::Vector3d.new(1, 0, 0) unless direction && direction.length > 0.001
        # Preserve the side of an axis lock that the cursor is pointing toward.
        direction.reverse! if axis_vector && @cursor && (@cursor - @anchor).dot(direction) < 0
        @cursor = @anchor.offset(direction, length)
        append_cursor(view)
        view.invalidate
      rescue StandardError => e
        @owner.report(e.message, 'error')
      end

      def onCancel(_reason, view)
        cancel_preview_refresh
        @typing = false
        if @waypoints.empty?
          @model.select_tool(nil)
        else
          @waypoints.clear
          @anchor = @mesh_key = @triangles = @lines = @preview_points = @preview_data = nil
          @axis = nil
          reanchor(view)
          @owner.preview if @owner.respond_to?(:preview)
          @owner.tool_progress(nil, 'Path cancelled - click to start again')
        end
        view.invalidate
      end

      def refresh_preview(force: false)
        points = @waypoints.dup
        points << @cursor if @cursor && !points.empty? && @cursor.distance(points.last) >= 50.mm
        if points.length < 2
          cancel_preview_refresh
          @preview_points = @triangles = @lines = @preview_data = nil
          return
        end
        stamp = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if !force && @preview_stamp && stamp - @preview_stamp < PREVIEW_INTERVAL
          # Keep the inference line responsive, then catch the final mouse
          # position even when it arrived inside the throttle interval.
          unless @refresh_timer
            @refresh_timer = UI.start_timer(PREVIEW_INTERVAL - (stamp - @preview_stamp), false) do
              @refresh_timer = nil
              if active? && !@suspended && valid_context?
                refresh_preview(force: true)
                @model.active_view.invalidate
              end
            end
          end
          return
        end
        cancel_preview_refresh
        @preview_stamp = stamp
        options = options_for(points)
        key = [options, points.first.to_a]
        return if @mesh_key == key
        data = Mesh.build(options, preview: :viewport)
        @preview_data = data
        transform = Geom::Transformation.translation(points.first.to_a)
        @preview_points = data[:points].map { |p| Geom::Point3d.new(p.map { |n| n / 25.4 }).transform(transform) }
        @triangles = data[:quads].flat_map { |a, b, c, d| [a, b, c, a, c, d].map { |i| @preview_points[i] } }
        stride = [(data[:quads].size / 900.0).ceil, 1].max
        @lines = data[:quads].each_slice(stride).flat_map { |slice| q = slice.first; [q[0], q[1], q[1], q[2]].map { |i| @preview_points[i] } }
        @mesh_key, @preview_error = key, nil
        if @anchor && @cursor
          Sketchup.set_status_text(Sketchup.format_length(@anchor.distance(@cursor)), SB_VCB_VALUE)
        end
        @owner.tool_progress(options['length'], "#{@waypoints.length - 1} runs set - click next corner or Finish", data[:requested_quads])
        @owner.tool_preview(data)
      rescue ArgumentError => e
        if @preview_error != e.message
          @owner.tool_progress(nil, e.message)
          @preview_error = e.message
        end
      end

      def cancel_preview_refresh
        UI.stop_timer(@refresh_timer) if @refresh_timer
        @refresh_timer = nil
      end

      def draw(view)
        super
        return if @suspended || !valid_context?
        view.drawing_color = 'DodgerBlue'
        view.line_width = 2
        view.draw(GL_LINE_STRIP, @waypoints) if @waypoints.length > 1
        view.draw_points(@waypoints, 6, 1, 'DodgerBlue') unless @waypoints.empty?
        if @preview_error && @anchor && @cursor
          view.drawing_color = 'red'
          view.draw(GL_LINES, [@anchor, @cursor])
        end
      end
    end
  end
end
