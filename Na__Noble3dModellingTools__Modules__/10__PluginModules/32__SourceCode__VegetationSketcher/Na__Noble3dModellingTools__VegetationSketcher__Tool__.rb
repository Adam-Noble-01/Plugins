# frozen_string_literal: true

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    class PlacementTool
      attr_reader :model, :preview_data

      def initialize(options, owner)
        @options, @owner = options.dup, owner
        @model = Sketchup.active_model
        @edit_path = @model.active_path
        @input = Sketchup::InputPoint.new
        @anchor_input = Sketchup::InputPoint.new
      end

      def activate
        @active = true
        status
        @owner.tool_progress(nil, 'Move into SketchUp to begin')
      end

      def deactivate(view)
        @active = false
        @owner.tool_stopped(self)
        view.invalidate
      end

      def suspend(view)
        @suspended = true
        @owner.tool_progress(nil, 'Placement paused while navigating')
        view.invalidate
      end

      def resume(view)
        @suspended = false
        status
        view.invalidate
      end

      def active?
        @active
      end

      def update_options(options)
        changed_preset = options['preset'] != @options['preset']
        @options = options.dup
        @anchor = nil if changed_preset
        @mesh_key = nil
        refresh_preview
        status
        @model.active_view.invalidate
      end

      def valid_context?
        Sketchup.active_model == @model && @model.active_path == @edit_path
      end

      def status
        text = if @options['preset'] == 'hedge'
                 @anchor ? 'Pick the hedge end or release the drag. Type a length. Left/Right: lock axis. Esc: cancel.' : 'Click and drag a hedgerow, or click its start and end. Left/Right: lock axis. R: new variation.'
               else
                 'Click to plant a whitecard ' + Options.label(@options) + '. Repeat to plant more. R: new variation. Esc: finish.'
               end
        Sketchup.status_text = text
        Sketchup.set_status_text(@options['preset'] == 'hedge' ? 'Length' : '', SB_VCB_LABEL)
      end

      def pick(x, y, view)
        return unless valid_context?
        @anchor ? @input.pick(view, x, y, @anchor_input) : @input.pick(view, x, y)
        if @input.valid?
          point = @input.position
          view.tooltip = @input.tooltip
        else
          ray = view.pickray(x, y)
          point = Geom.intersect_line_plane(ray, [@anchor || ORIGIN, Z_AXIS])
        end
        return unless point
        if @anchor && @options['preset'] == 'hedge'
          point = Geom::Point3d.new(point.x, point.y, @anchor.z)
          point.y = @anchor.y if @axis == :x
          point.x = @anchor.x if @axis == :y
        end
        @cursor = point
        refresh_preview
      end

      def onMouseMove(_flags, x, y, view)
        pick(x, y, view)
        view.invalidate
      rescue StandardError => e
        @owner.report(e.message, 'error')
      end

      def onLButtonDown(_flags, x, y, view)
        return unless valid_context?
        pick(x, y, view)
        return unless @cursor
        @down = [x, y]
        @second_click = !!@anchor
        if @options['preset'] == 'hedge' && !@anchor
          @anchor = @cursor.clone
          @anchor_input.copy!(@input) if @input.valid?
          @mesh_key = nil
        end
        status
        @owner.tool_progress(nil, 'Start point set - drag or click the end') if @anchor
      rescue StandardError => e
        @owner.report(e.message, 'error')
      end

      def onLButtonUp(_flags, x, y, view)
        return unless @down && valid_context?
        pick(x, y, view)
        dragged = Math.hypot(x - @down[0], y - @down[1]) > 5
        commit if @options['preset'] != 'hedge' || @second_click || dragged
        @down = nil
        view.invalidate
      rescue StandardError => e
        @down = nil
        @owner.report(e.message, 'error')
      end

      def onCancel(_reason, view)
        if @anchor
          @anchor = nil
          @mesh_key = nil
          refresh_preview
          status
        else
          @model.select_tool(nil)
        end
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when 39 then @axis = @axis == :x ? nil : :x
        when 37 then @axis = @axis == :y ? nil : :y
        when 40 then @axis = nil
        when 82 then @owner.new_variation
        else return false
        end
        if @anchor && @cursor && @axis
          @cursor.y = @anchor.y if @axis == :x
          @cursor.x = @anchor.x if @axis == :y
          refresh_preview
        end
        view.invalidate
        true
      end

      def enableVCB?
        @options['preset'] == 'hedge'
      end

      def onUserText(text, view)
        return unless @anchor && @options['preset'] == 'hedge'
        length = Sketchup.parse_length(text)
        raise ArgumentError, 'Enter a length from 50 mm to 100 m, for example 3m or 3000mm.' unless length && length >= 50.mm && length <= 100000.mm
        direction = @cursor && @cursor - @anchor
        direction = Geom::Vector3d.new(@axis == :y ? [0, 1, 0] : [1, 0, 0]) unless direction && direction.length > 0.001
        @cursor = @anchor.offset(direction, length)
        refresh_preview
        commit
        view.invalidate
      rescue StandardError => e
        @owner.report(e.message, 'error')
      end

      def placement
        if @options['preset'] == 'hedge' && @anchor && @cursor && @cursor.distance(@anchor) >= 50.mm
          xaxis = @cursor - @anchor
          xaxis.normalize!
          transform = Geom::Transformation.axes(@anchor, xaxis, Z_AXIS.cross(xaxis), Z_AXIS)
          [transform, @anchor.distance(@cursor) * 25.4]
        elsif @options['preset'] != 'hedge' && @cursor
          [Geom::Transformation.translation(@cursor.to_a), nil]
        end
      end

      def refresh_preview
        location = placement
        unless location
          @preview_points = @triangles = @lines = nil
          return
        end
        transform, length = location
        # Quantise the expensive mesh build while retaining the exact cursor end.
        sample_length = length ? [(length / 100.0).round * 100.0, 50.0].max : nil
        key = [@options, sample_length]
        unless @mesh_key == key
          @data = Mesh.build(@options, length: sample_length, preview: :viewport)
          @preview_data = @data
          @mesh_key = [@options.dup, sample_length]
          @owner.tool_preview(@data)
        end
        scale = length ? length / sample_length : 1.0
        @preview_points = @data[:points].map { |p| Geom::Point3d.new(p[0] * scale / 25.4, p[1] / 25.4, p[2] / 25.4).transform(transform) }
        @triangles = @data[:quads].flat_map { |a, b, c, d| [a, b, c, a, c, d].map { |i| @preview_points[i] } }
        stride = [(@data[:quads].size / 900.0).ceil, 1].max
        @lines = @data[:quads].each_slice(stride).flat_map { |slice| q = slice.first; [q[0], q[1], q[1], q[2]].map { |i| @preview_points[i] } }
        trunk_points = @data[:trunk][:points].map { |p| Geom::Point3d.new(p.map { |v| v / 25.4 }).transform(transform) }
        @data[:trunk][:faces].each do |face|
          (1...face.length - 1).each { |i| @triangles.concat([face[0], face[i], face[i + 1]].map { |j| trunk_points[j] }) }
        end
        @preview_points.concat(trunk_points)
        Sketchup.set_status_text(Sketchup.format_length(length / 25.4), SB_VCB_VALUE) if length
        # Do not flood HtmlDialog for every sub-pixel mouse move.
        progress_key = [length && (length / 10).round, @data[:requested_quads]]
        if progress_key != @progress_key
          @progress_key = progress_key
          count = length ? Mesh.count(Mesh.dimensions(@options, length), @options['resolution']) : @data[:requested_quads]
          @owner.tool_progress(length, 'Click or release to create', count)
        end
      end

      def draw(view)
        return if @suspended || !valid_context?
        @input.draw(view) if @input.valid? && @input.display?
        if @triangles
          view.drawing_color = Sketchup::Color.new(235, 243, 249, 185)
          view.draw(GL_TRIANGLES, @triangles)
          view.drawing_color = Sketchup::Color.new(74, 144, 217, 110)
          view.line_width = 1
          view.line_stipple = ''
          view.draw(GL_LINES, @lines) unless @lines.empty?
        end
        if @anchor
          view.draw_points([@anchor], 8, 1, 'DodgerBlue')
          if @cursor
            view.drawing_color = @axis == :x ? 'red' : (@axis == :y ? 'green' : 'DodgerBlue')
            view.line_width = 2
            view.draw(GL_LINES, [@anchor, @cursor])
          end
        end
      end

      def getExtents
        box = Geom::BoundingBox.new
        box.add(@model.bounds)
        box.add(@preview_points) if @preview_points && !@preview_points.empty?
        box.add(@anchor) if @anchor
        box
      end

      def commit
        location = placement
        raise ArgumentError, 'Draw a hedge at least 50 mm long.' unless location
        raise ArgumentError, 'Draw a hedge no longer than 100 m.' if location[1] && location[1] > 100000
        raise ArgumentError, 'The editing context changed. Start placement again.' unless valid_context?
        group = Builder.create(@model, @options, *location)
        @owner.created(group)
        @anchor = nil
        @progress_key = nil
        @mesh_key = nil
        @owner.new_variation if @options['vary']
        refresh_preview
        status
        @owner.tool_progress(nil, 'Created - draw another or Finish to edit')
      end
    end
  end
end
