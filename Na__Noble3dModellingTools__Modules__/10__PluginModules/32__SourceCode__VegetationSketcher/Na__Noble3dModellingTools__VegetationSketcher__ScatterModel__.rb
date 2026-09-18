# frozen_string_literal: true
# Noble Vegetation Scatter: source capture, persistent forest and surface data.
require 'json'
require_relative 'Na__Noble3dModellingTools__VegetationSketcher__ScatterCore__'

module Na__Noble3dModellingTools
    module Na__VegetationSketcher__ScatterModel
        NA_DICT = 'Na__VegetationSketcher__Scatter'.freeze
        NA_MAX_DABS = 2000

        def self.na_forest?(entity)
            entity.is_a?(Sketchup::Group) && entity.valid? && !!entity.get_attribute(NA_DICT, 'data')
        end

        def self.na_capture(model)
            selected = model.selection.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
            raise ArgumentError, 'Select one or more tree/shrub groups or components in SketchUp, then capture them.' if selected.empty?
            raise ArgumentError, 'Use up to 20 source items per forest.' if selected.length > 20
            selected.map do |entity|
                raise ArgumentError, 'A parametric forest cannot be its own source. Select individual trees or shrubs.' if na_forest?(entity)
                serializer = Na__VegetationSketcher__DataSerializer
                if serializer.Na__VegetationSketcher__DataSerializer__HasData?(entity)
                    options = serializer.Na__VegetationSketcher__DataSerializer__Load(entity)
                    raise ArgumentError, 'Select trees or shrubs rather than hedgerows.' if options['preset'] == 'hedge'
                end
                matrix = (model.edit_transform * entity.transformation).to_a
                matrix[12,3] = [0,0,0]
                linear = Geom::Transformation.new(matrix)
                corners = 8.times.map { |i| entity.definition.bounds.corner(i).transform(linear) }
                low, high = 3.times.map { |i| corners.map { |point| point.to_a[i] }.minmax }.transpose
                base = Geom::Transformation.translation([-(low[0]+high[0])/2, -(low[1]+high[1])/2, -low[2]]) * linear
                name = entity.name.to_s.empty? ? entity.definition.name : entity.name
                { 'key' => entity.persistent_id.to_s, 'definition_pid' => entity.definition.persistent_id,
                  'name' => name.empty? ? 'Vegetation item' : name, 'weight' => 100.0,
                  'transform' => base.to_a, 'material' => entity.material && entity.material.name }
            end
        end

        def self.na_load(group)
            raise ArgumentError, 'Select one Noble forest group first.' unless na_forest?(group)
            data = JSON.parse(group.get_attribute(NA_DICT, 'data'))
            raise ArgumentError, 'Unsupported forest settings.' unless data.is_a?(Hash) && data['version'] == 1
            data['options'] = Na__VegetationSketcher__ScatterCore.na_options(data['options'])
            Na__VegetationSketcher__ScatterCore.na_weights(data.fetch('sources'))
            raise ArgumentError, 'Invalid saved brush area.' unless data['dabs'].is_a?(Array) && data['dabs'].length <= NA_MAX_DABS
            data
        rescue JSON::ParserError, KeyError
            raise ArgumentError, 'The selected forest contains damaged settings.'
        end

        def self.na_definitions(model, sources, group = nil)
            library = group && group.entities.find { |e| e.is_a?(Sketchup::Group) && e.get_attribute(NA_DICT, 'role') == 'library' }
            saved = {}
            library.entities.each { |e| saved[e.get_attribute(NA_DICT, 'source_key')] = e.definition if e.respond_to?(:definition) } if library
            sources.map do |source|
                definition = saved[source['key']] || model.find_entity_by_persistent_id(source['definition_pid'])
                unless definition.is_a?(Sketchup::ComponentDefinition) && definition.valid?
                    raise ArgumentError, "Source '#{source['name']}' is missing. Capture the source items again."
                end
                definition
            end
        end

        # Resolve face paths afresh when regenerating: moved terrain is honoured,
        # while a deleted target is reported before existing plants are changed.
        class Surfaces
            def initialize(model); @model = model; @cache = {}; end
            def na_clear; @cache.clear; end
            def na_resolve(path)
                if @cache.key?(path)
                    cached = @cache[path]
                    raise ArgumentError, 'A painted surface was deleted. Restart the brush on a valid surface.' unless cached[:face].valid?
                    return cached
                end
                ip = @model.instance_path_from_pid_path(path)
                raise ArgumentError, 'A painted surface was deleted. The existing forest was preserved.' unless ip && ip.valid? && ip.leaf.is_a?(Sketchup::Face)
                face, tr = ip.leaf, ip.transformation
                parents = ip.to_a[0...-1]
                faces = face.all_connected.grep(Sketchup::Face)
                faces << face unless faces.include?(face)
                raise ArgumentError, 'Target terrain is too detailed (over 30,000 faces). Use a simpler planting surface.' if faces.length > 30000
                triangles = []
                faces.each do |f|
                    next unless @model.drawing_element_visible?(parents + [f])
                    mesh = f.mesh(0)
                    points = mesh.points.map { |point| point.transform(tr).to_a }
                    mesh.polygons.each do |polygon|
                        ids = polygon.map { |index| index.abs - 1 }
                        (1...ids.length-1).each { |i| triangles << [points[ids[0]], points[ids[i]], points[ids[i+1]]] }
                    end
                end
                core = Na__VegetationSketcher__ScatterCore
                local_mesh = face.mesh(0)
                polygon = local_mesh.polygons.first
                raise ArgumentError, 'The target face has no mesh.' unless polygon
                vertices = polygon.first(3).map { |i| local_mesh.point_at(i.abs).transform(tr).to_a }
                # Derive normals from transformed edges, including non-uniform scaling.
                normal = core.na_unit(core.na_cross(core.na_sub(vertices[1],vertices[0]), core.na_sub(vertices[2],vertices[0])))
                surface = { index: core::SurfaceIndex.new(triangles), transform: tr, normal: normal, path: path, face: face }
                faces.each { |f| @cache[(parents + [f]).map(&:persistent_id).join('.')] = surface }
                surface
            end

            def na_dab(raw)
                point = raw.fetch('point')
                raise ArgumentError, 'Invalid brush position.' unless point.is_a?(Array) && point.length == 3 && point.all? { |v| v.is_a?(Numeric) && v.finite? }
                surface = na_resolve(raw.fetch('surface'))
                normal = surface[:normal]
                if raw['tangents']
                    vectors = raw['tangents'].map { |v| Geom::Vector3d.new(v).transform(surface[:transform]).to_a }
                    normal = Na__VegetationSketcher__ScatterCore.na_unit(Na__VegetationSketcher__ScatterCore.na_cross(*vectors))
                end
                { point: Geom::Point3d.new(point).transform(surface[:transform]).to_a, normal: normal, surface: surface }
            end

            def na_project(dab, candidate, radius)
                core = Na__VegetationSketcher__ScatterCore
                normal = dab[:normal]
                origin = core.na_add(candidate,core.na_mul(normal,radius * 2 + 1))
                hit = dab[:surface][:index].na_hit(origin,core.na_mul(normal,-1),radius * 4 + 2)
                hit && hit.take(2)
            end

            def na_pick(view, x, y, excluded_keys = [])
                origin, direction = view.pickray(x,y).map(&:to_a)
                direction = Na__VegetationSketcher__ScatterCore.na_unit(direction)
                # Once a target is known, hit its cached surface through foliage.
                hits = @cache.values.uniq.filter_map do |surface|
                    hit = surface[:index].na_hit(origin,direction)
                    hit && [hit, surface]
                end
                cached = hits.min_by { |hit, _| hit[2] }
                picked = @model.raytest(view.pickray(x,y))
                if picked
                    point, entities = picked
                    blocked = entities.any? { |e| Na__VegetationSketcher__ScatterModel.na_forest?(e) || excluded_keys.include?(e.persistent_id.to_s) }
                    if !blocked && entities.last.is_a?(Sketchup::Face)
                        path = entities.map(&:persistent_id).join('.')
                        surface = na_resolve(path)
                        if !cached || point.distance(Geom::Point3d.new(origin)) <= cached[0][2] + 0.01
                            hit = surface[:index].na_hit(origin,direction)
                            return [point.to_a, surface, hit ? hit[1] : surface[:normal]]
                        end
                    end
                end
                cached && [cached[0][0], cached[1], cached[0][1]]
            end

            def na_encode(point, surface, normal = surface[:normal])
                inverse = surface[:transform].inverse
                axes = Na__VegetationSketcher__ScatterCore.na_basis(normal).take(2)
                { 'surface' => surface[:path], 'point' => Geom::Point3d.new(point).transform(inverse).to_a,
                  'tangents' => axes.map { |v| Geom::Vector3d.new(v).transform(inverse).to_a } }
            end
        end

        def self.na_generate(model, options, sources, dabs, surfaces = Surfaces.new(model))
            raise ArgumentError, 'The painted area is too large. Start another forest.' if dabs.length > NA_MAX_DABS
            resolved = dabs.map { |raw| surfaces.na_dab(raw) }
            Na__VegetationSketcher__ScatterCore.na_generate(options,sources,resolved) do |dab,point|
                surfaces.na_project(dab,point,options['radius']/25.4)
            end
        end

        def self.na_rebuild(model, group, options, sources, dabs, result = nil)
            if group && (!na_forest?(group) || group.locked? || !model.active_entities.include?(group))
                raise ArgumentError, 'Select an unlocked forest in the current editing context.'
            end
            options = Na__VegetationSketcher__ScatterCore.na_options(options)
            definitions = na_definitions(model,sources,group)
            result ||= na_generate(model,options,sources,dabs)
            # Validate transforms before starting a model operation.
            bases = sources.map { |s| Geom::Transformation.new(s.fetch('transform')) }
            model.start_operation(group ? 'Regenerate Noble Forest' : 'Paint Noble Forest', true)
            started = true
            if group
                group.make_unique
                owned = group.entities.select { |e| %w[plant library].include?(e.get_attribute(NA_DICT,'role')) }
                group.entities.erase_entities(owned) unless owned.empty?
            else
                group = model.active_entities.add_group
                group.name = 'Noble Parametric Forest'
                group.transformation = model.edit_transform.inverse
            end
            library = group.entities.add_group
            library.name = 'Scatter sources (hidden)'
            library.set_attribute(NA_DICT,'role','library')
            library.hidden = true
            library.transformation = Geom::Transformation.translation(result[:plants].first[:point]) unless result[:plants].empty?
            sources.each_with_index do |s,i|
                prototype = library.entities.add_instance(definitions[i],bases[i])
                prototype.set_attribute(NA_DICT,'source_key',s['key'])
                prototype.material = model.materials[s['material']] if s['material']
            end
            core = Na__VegetationSketcher__ScatterCore
            result[:plants].each do |plant|
                x, y, n = core.na_basis(plant[:normal])
                angle, size = plant.values_at(:yaw,:scale)
                a = core.na_mul(core.na_add(core.na_mul(x,Math.cos(angle)),core.na_mul(y,Math.sin(angle))),size)
                b = core.na_mul(core.na_add(core.na_mul(x,-Math.sin(angle)),core.na_mul(y,Math.cos(angle))),size)
                # Explicit matrix retains the requested uniform size as well as
                # orientation, without relying on axis-vector normalisation.
                transform = Geom::Transformation.new([*a,0,*b,0,*core.na_mul(n,size),0,*plant[:point],1])
                i = plant[:source]
                instance = group.entities.add_instance(definitions[i],transform * bases[i])
                instance.name = sources[i]['name']
                instance.material = model.materials[sources[i]['material']] if sources[i]['material']
                instance.set_attribute(NA_DICT,'role','plant')
            end
            saved_sources = sources.each_with_index.map { |s,i| s.merge('definition_pid' => definitions[i].persistent_id) }
            data = { 'version' => 1, 'geometry_units' => 'inches', 'options' => options, 'sources' => saved_sources,
                     'dabs' => dabs, 'count' => result[:plants].length, 'capped' => result[:capped] }
            group.set_attribute(NA_DICT,'data',JSON.generate(data))
            model.commit_operation
            group
        rescue StandardError
            model.abort_operation if started
            raise
        end
    end
end
