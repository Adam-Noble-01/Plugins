# frozen_string_literal: true
# Lightweight brush: rings/points while dragging; one undoable commit on release.
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__ScatterModel__'
module Na__Noble3dModellingTools
    class Na__VegetationSketcher__ScatterTool
        attr_reader :na_group
        def initialize(model, options, sources, owner)
            @na_model, @na_options, @na_sources, @na_owner = model, options, sources, owner
            @na_path = (model.active_path || []).dup
            @na_surfaces = Na__VegetationSketcher__ScatterModel::Surfaces.new(model)
            @na_dabs, @na_stroke = [], []
        end

        def activate
            @na_active = true
            Sketchup.status_text = 'Scatter: drag on a face or terrain. Release to plant. Esc cancels this stroke; Enter finishes.'
        end
        def deactivate(view)
            @na_active = false
            @na_stroke.clear
            @na_owner.na_tool_finished(self)
            view.invalidate
        end
        def suspend(view); @na_stroke.clear; @na_down = false; view.invalidate; end
        def resume(view); activate; view.invalidate; end
        def na_active?; @na_active; end
        def na_context?
            Sketchup.active_model == @na_model && ( @na_model.active_path || [] ) == @na_path
        end
        def na_stop; @na_model.select_tool(nil) if @na_active && Sketchup.active_model == @na_model; end

        def na_pick(x,y,view)
            return unless na_context?
            @na_hit = @na_surfaces.na_pick(view,x,y,@na_sources.map { |source| source['key'] })
            view.tooltip = @na_hit ? 'Drag to paint vegetation' : 'Point at a face or terrain surface'
            return unless @na_hit
            point, surface, normal = @na_hit
            core = Na__VegetationSketcher__ScatterCore
            bx, by, = core.na_basis(normal)
            radius = @na_options['radius']/25.4
            @na_ring = 49.times.map do |i|
                a = i * Math::PI * 2 / 48
                Geom::Point3d.new(core.na_add(point,core.na_add(core.na_mul(bx,Math.cos(a)*radius),core.na_mul(by,Math.sin(a)*radius))))
            end
        end

        def na_add_dab
            return unless @na_hit
            point, surface, normal = @na_hit
            core = Na__VegetationSketcher__ScatterCore
            step = @na_options['radius']/25.4 * 0.35
            if @na_last && @na_last_surface == surface
                distance = core.na_length(core.na_sub(point,@na_last))
                return if distance < step
                count = (distance/step).floor
                raise ArgumentError, 'Brush movement is too long. Use shorter strokes.' if count > 100
                count.times do |i|
                    p = core.na_add(@na_last,core.na_mul(core.na_sub(point,@na_last),(i+1)*step/distance))
                    dab = { point: p, normal: normal, surface: surface }
                    projected = @na_surfaces.na_project(dab,p,@na_options['radius']/25.4)
                    @na_stroke << @na_surfaces.na_encode(projected[0],surface,projected[1]) if projected
                end
            else
                @na_stroke << @na_surfaces.na_encode(point,surface,normal)
            end
            @na_last, @na_last_surface = point, surface
            raise ArgumentError, 'This forest has reached its brush-area limit. Finish and paint a new forest.' if @na_stroke.length + @na_dabs.length > Na__VegetationSketcher__ScatterModel::NA_MAX_DABS
        end

        def onMouseMove(_flags,x,y,view)
            na_pick(x,y,view)
            na_add_dab if @na_down
            view.invalidate
        rescue StandardError => error
            @na_down = false
            @na_stroke.clear
            @na_owner.na_status(error.message,true)
        end
        def onLButtonDown(_flags,x,y,view)
            raise ArgumentError, 'The editing context changed. Restart the scatter brush.' unless na_context?
            na_pick(x,y,view)
            return unless @na_hit
            # Honour native Undo between strokes by re-reading the group's data.
            if @na_group && @na_group.valid?
                @na_dabs = Na__VegetationSketcher__ScatterModel.na_load(@na_group)['dabs']
            elsif @na_group
                @na_group, @na_dabs = nil, []
            end
            @na_down, @na_stroke, @na_last = true, [], nil
            na_add_dab
            view.invalidate
        rescue StandardError => error
            @na_owner.na_status(error.message,true)
        end
        def onLButtonUp(_flags,x,y,view)
            return unless @na_down
            @na_down = false
            na_pick(x,y,view)
            na_add_dab
            return if @na_stroke.empty?
            raise ArgumentError, 'The editing context changed. Restart the scatter brush.' unless na_context?
            candidate = @na_dabs + @na_stroke
            store = Na__VegetationSketcher__ScatterModel
            result = store.na_generate(@na_model,@na_options,@na_sources,candidate,@na_surfaces)
            @na_group = store.na_rebuild(@na_model,@na_group,@na_options,@na_sources,candidate,result)
            @na_dabs = candidate
            @na_owner.na_painted(@na_group,result)
        rescue StandardError => error
            @na_owner.na_status(error.message,true)
        ensure
            @na_stroke = []
            view.invalidate
        end
        def onCancel(_reason,view)
            if @na_down
                @na_down = false
                @na_stroke.clear
            else
                na_stop
            end
            view.invalidate
        end
        def onReturn(_view); na_stop; end
        def getMenu(menu); menu.add_item('Finish scatter brush') { na_stop }; end
        def draw(view)
            return unless na_context? && @na_active && @na_hit
            view.drawing_color = Sketchup::Color.new(74,144,217)
            view.line_width = 2
            view.line_stipple = ''
            view.draw(GL_LINE_STRIP,@na_ring)
            points = @na_stroke.last(300).map { |raw| Geom::Point3d.new(@na_surfaces.na_dab(raw)[:point]) }
            view.draw_points(points,5,1,'DodgerBlue') unless points.empty?
        end
        def getExtents
            box = Geom::BoundingBox.new
            box.add(@na_model.bounds)
            box.add(@na_ring) if @na_ring
            box
        end
    end
end
