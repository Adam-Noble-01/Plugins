# =============================================================================
# NA NOBLE3D MODELLING TOOLS - VEGETATION SKETCHER - PLACEMENT TOOL
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__VegetationSketcher__Tool__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__VegetationSketcher__PlacementTool
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Click-to-plant trees and shrubs with optional random size,
#              height stretch, turn and lean; and a simple two-point hedge
# CREATED    : 2026
#
# SketchUp Tool API names stay unprefixed. Instance helpers use na_*.
# View drawing, InputPoints and pick rays are always global.
#
# =============================================================================

require_relative 'Na__Noble3dModellingTools__VegetationSketcher__Placement__'

module Na__Noble3dModellingTools

    class Na__VegetationSketcher__PlacementTool

# -----------------------------------------------------------------------------
# REGION | Construction
# -----------------------------------------------------------------------------

        attr_reader :na_model, :na_preview_data

        def initialize(options, owner, placement = nil)
            @na_options = options.dup
            @na_owner = owner
            @na_model = Sketchup.active_model
            @na_edit_path = @na_model.active_path
            @na_input = Sketchup::InputPoint.new
            @na_anchor_input = Sketchup::InputPoint.new
            @na_placement = placement
            na_reroll
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Tool Lifecycle
# -----------------------------------------------------------------------------

        def activate
            @na_active = true
            na_status
            @na_owner.na_tool_progress(nil, 'Move into SketchUp to begin')
        end

        def deactivate(view)
            @na_active = false
            @na_owner.na_tool_stopped(self)
            view.invalidate
        end

        def suspend(view)
            @na_suspended = true
            @na_owner.na_tool_progress(nil, 'Placement paused while navigating')
            view.invalidate
        end

        def resume(view)
            @na_suspended = false
            na_status
            view.invalidate
        end

        def enableVCB?
            @na_options['preset'] == 'hedge'
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Instance Helpers
# -----------------------------------------------------------------------------

        def na_active?
            @na_active
        end

        def na_valid_context?
            Sketchup.active_model == @na_model && @na_model.active_path == @na_edit_path
        end

        def na_update_options(options)
            changed_preset = options['preset'] != @na_options['preset']
            @na_options = options.dup
            @na_anchor = nil if changed_preset
            @na_mesh_key = nil
            na_refresh_preview
            na_status
            @na_model.active_view.invalidate
        end

        # Placement ranges are separate from form options: they never rebuild
        # the mesh or touch saved vegetation, only the next plant's transform.
        def na_update_placement(placement)
            @na_placement = placement
            na_reroll
            na_refresh_preview
            na_status
            @na_model.active_view.invalidate
        end

        def na_varied?
            @na_options['preset'] != 'hedge' && !!(@na_placement && @na_placement['enabled'])
        end

        def na_reroll
            @na_roll = Na__VegetationSketcher__Placement.Na__VegetationSketcher__Placement__Roll(na_varied? ? @na_placement : nil)
            @na_progress_key = nil
        end

        def na_roll_text
            na_varied? ? ' Next: ' + Na__VegetationSketcher__Placement.Na__VegetationSketcher__Placement__Describe(@na_roll) + '.' : ''
        end

        def na_status
            text = if @na_options['preset'] == 'hedge'
                       @na_anchor ? 'Pick the hedge end or release the drag. Type a length. Left/Right: lock axis. Esc: cancel.' : 'Click and drag a hedgerow, or click its start and end. Left/Right: lock axis. R: new variation.'
                   else
                       'Click to plant a whitecard ' + Na__VegetationSketcher__Options.Na__VegetationSketcher__Options__Label(@na_options) + '. Repeat to plant more. R: new variation.' + na_roll_text + ' Esc: finish.'
                   end
            Sketchup.status_text = text
            Sketchup.set_status_text(@na_options['preset'] == 'hedge' ? 'Length' : '', SB_VCB_LABEL)
        end

        def na_pick(x, y, view)
            return unless na_valid_context?

            @na_anchor ? @na_input.pick(view, x, y, @na_anchor_input) : @na_input.pick(view, x, y)
            if @na_input.valid?
                point = @na_input.position
                view.tooltip = @na_input.tooltip
            else
                ray = view.pickray(x, y)
                point = Geom.intersect_line_plane(ray, [@na_anchor || ORIGIN, Z_AXIS])
            end
            return unless point

            if @na_anchor && @na_options['preset'] == 'hedge'
                point = Geom::Point3d.new(point.x, point.y, @na_anchor.z)
                point.y = @na_anchor.y if @na_axis == :x
                point.x = @na_anchor.x if @na_axis == :y
            end
            @na_cursor = point
            na_refresh_preview
        end

        def na_placement
            if @na_options['preset'] == 'hedge' && @na_anchor && @na_cursor && @na_cursor.distance(@na_anchor) >= 50.mm
                xaxis = @na_cursor - @na_anchor
                xaxis.normalize!
                transform = Geom::Transformation.axes(@na_anchor, xaxis, Z_AXIS.cross(xaxis), Z_AXIS)
                [transform, @na_anchor.distance(@na_cursor) * 25.4]
            elsif @na_options['preset'] != 'hedge' && @na_cursor
                if na_varied?
                    [Geom::Transformation.new(Na__VegetationSketcher__Placement.Na__VegetationSketcher__Placement__Matrix(@na_cursor, @na_roll)), nil]
                else
                    [Geom::Transformation.translation(@na_cursor.to_a), nil]
                end
            end
        end

        def na_commit
            location = na_placement
            raise ArgumentError, 'Draw a hedge at least 50 mm long.' unless location
            raise ArgumentError, 'Draw a hedge no longer than 100 m.' if location[1] && location[1] > 100000
            raise ArgumentError, 'The editing context changed. Start placement again.' unless na_valid_context?

            group = Na__VegetationSketcher__Builder.Na__VegetationSketcher__Builder__Create(@na_model, @na_options, *location)
            @na_owner.na_created(group)
            @na_anchor = nil
            @na_mesh_key = nil
            na_reroll
            @na_owner.na_new_variation if @na_options['vary']
            na_refresh_preview
            na_status
            @na_owner.na_tool_progress(nil, 'Created - draw another or Finish to edit')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Pointer, Keyboard and VCB
# -----------------------------------------------------------------------------

        def onMouseMove(_flags, x, y, view)
            na_pick(x, y, view)
            view.invalidate
        rescue StandardError => error
            @na_owner.na_report(error.message, 'error')
        end

        def onLButtonDown(_flags, x, y, view)
            return unless na_valid_context?

            na_pick(x, y, view)
            return unless @na_cursor

            @na_down = [x, y]
            @na_second_click = !!@na_anchor
            if @na_options['preset'] == 'hedge' && !@na_anchor
                @na_anchor = @na_cursor.clone
                @na_anchor_input.copy!(@na_input) if @na_input.valid?
                @na_mesh_key = nil
            end
            na_status
            @na_owner.na_tool_progress(nil, 'Start point set - drag or click the end') if @na_anchor
        rescue StandardError => error
            @na_owner.na_report(error.message, 'error')
        end

        def onLButtonUp(_flags, x, y, view)
            return unless @na_down && na_valid_context?

            na_pick(x, y, view)
            dragged = Math.hypot(x - @na_down[0], y - @na_down[1]) > 5
            na_commit if @na_options['preset'] != 'hedge' || @na_second_click || dragged
            @na_down = nil
            view.invalidate
        rescue StandardError => error
            @na_down = nil
            @na_owner.na_report(error.message, 'error')
        end

        def onCancel(_reason, view)
            if @na_anchor
                @na_anchor = nil
                @na_mesh_key = nil
                na_refresh_preview
                na_status
            else
                @na_model.select_tool(nil)
            end
            view.invalidate
        end

        def onKeyDown(key, _repeat, _flags, view)
            case key
            when 39 then @na_axis = @na_axis == :x ? nil : :x
            when 37 then @na_axis = @na_axis == :y ? nil : :y
            when 40 then @na_axis = nil
            when 82
                na_reroll
                @na_owner.na_new_variation
            else return false
            end
            if @na_anchor && @na_cursor && @na_axis
                @na_cursor.y = @na_anchor.y if @na_axis == :x
                @na_cursor.x = @na_anchor.x if @na_axis == :y
                na_refresh_preview
            end
            view.invalidate
            true
        end

        def onUserText(text, view)
            return unless @na_anchor && @na_options['preset'] == 'hedge'

            length = Sketchup.parse_length(text)
            raise ArgumentError, 'Enter a length from 50 mm to 100 m, for example 3m or 3000mm.' unless length && length >= 50.mm && length <= 100000.mm

            direction = @na_cursor && @na_cursor - @na_anchor
            direction = Geom::Vector3d.new(@na_axis == :y ? [0, 1, 0] : [1, 0, 0]) unless direction && direction.length > 0.001
            @na_cursor = @na_anchor.offset(direction, length)
            na_refresh_preview
            na_commit
            view.invalidate
        rescue StandardError => error
            @na_owner.na_report(error.message, 'error')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Preview Mesh and Draw
# -----------------------------------------------------------------------------

        def na_refresh_preview
            location = na_placement
            unless location
                @na_preview_points = @na_triangles = @na_lines = nil
                return
            end

            transform, length = location
            sample_length = length ? [(length / 100.0).round * 100.0, 50.0].max : nil
            key = [@na_options, sample_length]
            unless @na_mesh_key == key
                @na_data = Na__VegetationSketcher__Mesh.Na__VegetationSketcher__Mesh__Build(@na_options, length: sample_length, preview: :viewport)
                @na_preview_data = @na_data
                @na_mesh_key = [@na_options.dup, sample_length]
                @na_owner.na_tool_preview(@na_data)
            end
            scale = length ? length / sample_length : 1.0
            @na_preview_points = @na_data[:points].map { |p| Geom::Point3d.new(p[0] * scale / 25.4, p[1] / 25.4, p[2] / 25.4).transform(transform) }
            @na_triangles = @na_data[:quads].flat_map { |a, b, c, d| [a, b, c, a, c, d].map { |i| @na_preview_points[i] } }
            stride = [(@na_data[:quads].size / 900.0).ceil, 1].max
            @na_lines = @na_data[:quads].each_slice(stride).flat_map { |slice| q = slice.first; [q[0], q[1], q[1], q[2]].map { |i| @na_preview_points[i] } }
            na_append_trunk_preview(transform)
            Sketchup.set_status_text(Sketchup.format_length(length / 25.4), SB_VCB_VALUE) if length
            na_report_progress(length)
        end

        def na_append_trunk_preview(transform)
            trunk_points = @na_data[:trunk][:points].map { |p| Geom::Point3d.new(p.map { |v| v / 25.4 }).transform(transform) }
            @na_data[:trunk][:faces].each do |face|
                (1...face.length - 1).each { |i| @na_triangles.concat([face[0], face[i], face[i + 1]].map { |j| trunk_points[j] }) }
            end
            @na_preview_points.concat(trunk_points)
        end

        def na_report_progress(length)
            progress_key = [length && (length / 10).round, @na_data[:requested_quads]]
            return if progress_key == @na_progress_key

            @na_progress_key = progress_key
            count = length ? Na__VegetationSketcher__Mesh.Na__VegetationSketcher__Mesh__Count(Na__VegetationSketcher__Mesh.Na__VegetationSketcher__Mesh__Dimensions(@na_options, length), @na_options['resolution']) : @na_data[:requested_quads]
            phase = na_varied? ? 'Next plant ' + Na__VegetationSketcher__Placement.Na__VegetationSketcher__Placement__Describe(@na_roll) : 'Click or release to create'
            @na_owner.na_tool_progress(length, phase, count)
        end

        def draw(view)
            return if @na_suspended || !na_valid_context?

            @na_input.draw(view) if @na_input.valid? && @na_input.display?
            if @na_triangles
                view.drawing_color = Sketchup::Color.new(235, 243, 249, 185)
                view.draw(GL_TRIANGLES, @na_triangles)
                view.drawing_color = Sketchup::Color.new(74, 144, 217, 110)
                view.line_width = 1
                view.line_stipple = ''
                view.draw(GL_LINES, @na_lines) unless @na_lines.empty?
            end
            if @na_anchor
                view.draw_points([@na_anchor], 8, 1, 'DodgerBlue')
                if @na_cursor
                    view.drawing_color = @na_axis == :x ? 'red' : (@na_axis == :y ? 'green' : 'DodgerBlue')
                    view.line_width = 2
                    view.draw(GL_LINES, [@na_anchor, @na_cursor])
                end
            end
        end

        def getExtents
            box = Geom::BoundingBox.new
            box.add(@na_model.bounds)
            box.add(@na_preview_points) if @na_preview_points && !@na_preview_points.empty?
            box.add(@na_anchor) if @na_anchor
            box
        end

# endregion -------------------------------------------------------------------

    end # class Na__VegetationSketcher__PlacementTool
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
