# frozen_string_literal: true
# One undoable, parametric component per painted face stroke. The original face
# is only read; the saved wall loops clip future density/leaf/flower edits too.
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__ScatterCore__'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__VineForms__'

module Na__Noble3dModellingTools
    class Na__VegetationSketcher__VineTool
        attr_reader :na_model, :na_preview_data
        Core = Na__VegetationSketcher__ScatterCore
        Forms = Na__VegetationSketcher__VineForms

        def initialize(options, owner)
            @na_options, @na_owner = options.dup, owner
            @na_model = Sketchup.active_model
            @na_edit_path = (@na_model.active_path || []).dup
            @na_paths = []
            @na_revision = 0
        end

        def activate
            @na_active = true
            Sketchup.status_text = 'Vines: drag along a wall face; release to grow. One face per stroke. Esc cancels a stroke; Enter finishes.'
        end
        def na_active?; !!@na_active; end
        def na_valid_context?
            Sketchup.active_model == @na_model && (@na_model.active_path || []) == @na_edit_path
        end
        def deactivate(view)
            @na_active = false
            na_clear_stroke
            @na_owner.na_tool_stopped(self)
            view.invalidate
        end
        def suspend(view); na_clear_stroke; @na_surface=nil; @na_suspended=true; view.invalidate; end
        def resume(view); @na_suspended=false; activate; view.invalidate; end
        def na_clear_stroke
            @na_down=false
            @na_paths=[]
            @na_triangles=[]
            @na_preview_data=nil
            @na_last_preview=nil
            @na_preview_revision=nil
            @na_break=true
        end
        def na_update_options(options)
            @na_options=options.dup
            na_preview(true) if @na_down
            @na_model.active_view.invalidate
        end

        # Derive an orthonormal wall frame from transformed triangle edges, so
        # mirrored/nonuniformly scaled nested components work on either side.
        def na_surface(point, entities, ray_direction)
            face=entities.last
            return nil unless face.is_a?(Sketchup::Face) && face.valid?
            transform=Sketchup::InstancePath.new(entities).transformation
            mesh=face.mesh(0)
            poly=mesh.polygons.first
            return nil unless poly
            a,b,c=poly.first(3).map { |id| mesh.point_at(id.abs).transform(transform).to_a }
            normal=Core.na_unit(Core.na_cross(Core.na_sub(b,a),Core.na_sub(c,a)))
            normal=Core.na_mul(normal,-1) if Core.na_dot(normal,ray_direction)>0
            up=Core.na_sub([0,0,1],Core.na_mul(normal,normal[2]))
            up=Core.na_sub([0,1,0],Core.na_mul(normal,normal[1])) if Core.na_length(up)<0.01
            up=Core.na_unit(up)
            right=Core.na_unit(Core.na_cross(normal,up))
            frame=Geom::Transformation.new([*right,0,*normal,0,*up,0,*point.to_a,1])
            inverse=frame.inverse
            loops=face.loops.map do |loop|
                loop.vertices.map do |vertex|
                    p=vertex.position.transform(transform).transform(inverse).to_a
                    [p[0]*25.4,p[2]*25.4]
                end
            end
            raise ArgumentError, 'This wall boundary is too detailed. Paint a simpler face.' if loops.sum(&:length)>2000
            { face: face, path: entities.map(&:persistent_id), frame: frame, inverse: inverse,
              loops: loops, normal: normal, origin: point.to_a }
        end

        def na_on_surface(surface, ray)
            return nil unless surface && surface[:face].valid?
            origin,direction=ray.map(&:to_a)
            denominator=Core.na_dot(direction,surface[:normal])
            return nil if denominator.abs<1.0e-9
            t=Core.na_dot(Core.na_sub(surface[:origin],origin),surface[:normal])/denominator
            return nil if t<0
            point=Geom::Point3d.new(Core.na_add(origin,Core.na_mul(direction,t)))
            local=point.transform(surface[:inverse]).to_a
            xy=[local[0]*25.4,local[2]*25.4]
            Forms.na_inside?(xy,surface[:loops]) ? xy : nil
        end

        def na_pick(x,y,view)
            @na_hit=nil
            return unless na_valid_context?
            ray=view.pickray(x,y)
            current_ray=ray
            picked=nil
            # Ignore existing Noble foliage; never hide or mutate user geometry.
            32.times do
                picked=@na_model.raytest(current_ray)
                break unless picked
                vegetation=picked[1].any? { |entity| Na__VegetationSketcher__DataSerializer.Na__VegetationSketcher__DataSerializer__HasData?(entity) }
                break unless vegetation
                direction=Core.na_unit(ray[1].to_a)
                current_ray=[Geom::Point3d.new(Core.na_add(picked[0].to_a,Core.na_mul(direction,0.01))),ray[1]]
                picked=nil
            end
            if !@na_hit && picked && picked[1].last.is_a?(Sketchup::Face)
                path=picked[1].map(&:persistent_id)
                if @na_down
                    @na_hit=na_on_surface(@na_surface,ray) if @na_surface[:path]==path
                else
                    if !@na_surface || @na_surface[:path]!=path || !@na_surface[:face].valid? || Core.na_dot(@na_surface[:normal],ray[1].to_a)>0
                        @na_surface=na_surface(picked[0],picked[1],ray[1].to_a)
                    end
                    @na_hit=na_on_surface(@na_surface,ray)
                end
            end
            view.tooltip=@na_hit ? 'Drag to grow a vine; release to create' : 'Point at the same wall face, or release to start another stroke'
        end

        def na_add_point(force=false)
            unless @na_hit
                @na_break=true
                return
            end
            if @na_paths.empty? || @na_break
                @na_paths << [@na_hit.dup]
                @na_break=false
            else
                last=@na_paths.last.last
                distance=Math.hypot(@na_hit[0]-last[0],@na_hit[1]-last[1])
                return if distance < (force ? 1.0 : (@na_options['vine_width']/10.0).clamp(25,80))
                if Forms.na_supported_segment?(last,@na_hit,@na_surface[:loops])
                    @na_paths.last << @na_hit.dup
                else
                    @na_paths << [@na_hit.dup]
                end
            end
            raise ArgumentError, 'Stroke limit reached. Release and paint another stroke.' if @na_paths.sum(&:length)>Forms::NA_MAX_POINTS
            @na_revision += 1
        end

        def na_stroke
            { 'paths' => @na_paths.select { |path| path.length>1 }, 'loops' => @na_surface[:loops] }
        end

        def na_preview(force=false)
            return unless @na_paths.any? { |path| path.length>1 }
            return if !force && @na_preview_revision == @na_revision
            now=Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return if !force && @na_last_preview && now-@na_last_preview<0.15
            @na_last_preview=now
            @na_preview_revision=@na_revision
            config=@na_options.merge('vine_stroke'=>Forms.na_stroke(na_stroke))
            @na_preview_data=Na__VegetationSketcher__Mesh.Na__VegetationSketcher__Mesh__Build(config,preview: :viewport)
            points=@na_preview_data[:points].map { |p| Geom::Point3d.new(p.map { |v| v/25.4 }).transform(@na_surface[:frame]) }
            @na_triangles=@na_preview_data[:quads].flat_map { |a,b,c,d| [points[a],points[b],points[c],points[a],points[c],points[d]] }
            @na_owner.na_tool_preview(@na_preview_data)
            @na_owner.na_tool_progress(nil,'Painting vine · release to create',@na_preview_data[:quads].length)
        end

        def onMouseMove(_flags,x,y,view)
            return if @na_suspended
            na_pick(x,y,view)
            if @na_down
                na_add_point
                na_preview
            end
            view.invalidate
        rescue StandardError => error
            na_fail(error,view)
        end
        def onLButtonDown(_flags,x,y,view)
            raise ArgumentError, 'Editing context changed. Restart Paint vines.' unless na_valid_context?
            @na_surface=nil # Refresh geometry/transforms once at the start of each stroke.
            na_pick(x,y,view)
            return unless @na_hit
            na_clear_stroke
            @na_down=true
            na_add_point
            view.invalidate
        rescue StandardError => error
            na_fail(error,view)
        end
        def onLButtonUp(_flags,x,y,view)
            return unless @na_down
            na_pick(x,y,view)
            na_add_point(true)
            na_finish_path
            view.invalidate
        rescue StandardError => error
            na_fail(error,view)
        end
        def na_finish_path
            return unless @na_down
            raise ArgumentError, 'Editing context changed. Restart Paint vines.' unless na_valid_context?
            raise ArgumentError, 'The painted face was deleted. Paint on a valid face.' unless @na_surface[:face].valid?
            config=@na_options.merge('vine_stroke'=>Forms.na_stroke(na_stroke))
            group=Na__VegetationSketcher__Builder.Na__VegetationSketcher__Builder__Create(@na_model,config,@na_surface[:frame])
            na_clear_stroke
            @na_owner.na_created(group)
            @na_owner.na_new_variation if @na_options['vary']
            @na_owner.na_tool_progress(nil,'Vine created · paint another stroke or Finish to edit')
        end
        def na_fail(error,view)
            na_clear_stroke
            @na_owner.na_report(error.message,'error')
            view.invalidate
        end
        def onCancel(_reason,view)
            @na_down ? na_clear_stroke : @na_model.select_tool(nil)
            view.invalidate
        end
        def onReturn(view)
            na_finish_path
            @na_model.select_tool(nil)
        rescue StandardError => error
            na_fail(error,view)
        end
        def onKeyDown(key,_repeat,_flags,view)
            @na_owner.na_new_variation if key==82
            view.invalidate
        end
        def getMenu(menu); menu.add_item('Finish painting vines') { onReturn(@na_model.active_view) }; end
        def draw(view)
            return unless @na_active && !@na_suspended && na_valid_context?
            view.drawing_color=Sketchup::Color.new(242,246,240,210)
            view.draw(GL_TRIANGLES,@na_triangles) if @na_triangles && !@na_triangles.empty?
            return unless @na_surface
            view.drawing_color=Sketchup::Color.new(74,144,217)
            view.line_width=2
            view.line_stipple=''
            @na_paths.each do |path|
                points=path.map { |p| Geom::Point3d.new(p[0]/25.4,@na_options['vine_offset']/25.4,p[1]/25.4).transform(@na_surface[:frame]) }
                view.draw(GL_LINE_STRIP,points) if points.length>1
            end
            if @na_hit
                radius=@na_options['vine_width']/2
                ring=33.times.map do |i|
                    a=i*Math::PI/16
                    Geom::Point3d.new((@na_hit[0]+Math.cos(a)*radius)/25.4,@na_options['vine_offset']/25.4,(@na_hit[1]+Math.sin(a)*radius)/25.4).transform(@na_surface[:frame])
                end
                view.draw(GL_LINE_STRIP,ring)
            end
        end
        def getExtents
            box=Geom::BoundingBox.new
            box.add(@na_model.bounds)
            box.add(@na_triangles) if @na_triangles && !@na_triangles.empty?
            box
        end
    end
end
