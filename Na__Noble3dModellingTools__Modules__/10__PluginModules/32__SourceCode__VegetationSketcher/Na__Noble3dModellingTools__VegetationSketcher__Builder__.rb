# frozen_string_literal: true

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    module Builder
      DICTIONARY = 'Na__VegetationSketcher'.freeze

      def self.vegetation?(entity)
        DataSerializer.has_data?(entity)
      end

      def self.populate(group, data, o, model)
        material = model.materials.find { |m| m.get_attribute(DICTIONARY, 'whitecard') && m.color.to_a[0, 3] == [255, 255, 255] && m.alpha == 1.0 && !m.texture }
        unless material
          material = model.materials.add('Noble Whitecard Vegetation')
          material.color = Sketchup::Color.new(255, 255, 255)
          material.set_attribute(DICTIONARY, 'whitecard', true)
        end
        root_entities = DataSerializer.entities(group)
        foliage = o['preset'] == 'tree' ? root_entities.add_group : group
        foliage.name = 'Whitecard canopy' unless foliage == group
        mesh = Geom::PolygonMesh.new(data[:points].length, data[:quads].length * 2)
        ids = data[:points].map { |p| mesh.add_point(p.map { |v| v / 25.4 }) }
        data[:quads].each do |q|
          a, b, c, d = q.map { |i| ids[i] }
          # Non-planar quads are represented by two triangles. Only their shared
          # diagonal is hidden, retaining the shared quad-grid vertices.
          mesh.add_polygon(a, b, -c)
          mesh.add_polygon(-a, c, d)
        end
        flags = Geom::PolygonMesh::HIDE_BASED_ON_INDEX | Geom::PolygonMesh::SOFTEN_BASED_ON_INDEX | Geom::PolygonMesh::SMOOTH_SOFT_EDGES
        foliage_entities = DataSerializer.entities(foliage)
        raise 'Could not create the vegetation mesh.' unless foliage_entities.fill_from_mesh(mesh, true, flags, material, material)
        # Hide grid edges for whitecard output, leaving the optional smooth flag
        # independent from geometric rounding. Quads remain inspectable via Hidden Geometry.
        apply_shading(foliage_entities, o['smooth'])
        if o['preset'] == 'tree'
          trunk = root_entities.add_group
          trunk.name = o['tree_type'] == 'english_oak' ? 'Whitecard trunk and branches' : 'Whitecard trunk'
          pm = Geom::PolygonMesh.new
          ti = data[:trunk][:points].map { |p| pm.add_point(p.map { |v| v / 25.4 }) }
          data[:trunk][:faces].each do |f|
            indices = f.map { |i| ti[i] }
            if indices.length == 4
              a, b, c, d = indices
              pm.add_polygon(a, b, -c)
              pm.add_polygon(-a, c, d)
            else
              pm.add_polygon(indices)
            end
          end
          raise 'Could not create the tree trunk and branches.' unless trunk.entities.fill_from_mesh(pm, true, flags, material, material)
          apply_shading(trunk.entities, o['smooth'])
        end
        group.material = material
        DataSerializer.save(model, group, o, data[:quads].length)
        group
      end

      def self.apply_shading(entities, enabled)
        threshold = 40.3 * Math::PI / 180.0
        entities.grep(Sketchup::Edge).each do |edge|
          diagonal = edge.soft?
          faces = edge.faces
          rounded = enabled && faces.length == 2 && faces[0].normal.angle_between(faces[1].normal) <= threshold
          edge.soft = diagonal || rounded
          edge.smooth = !!rounded
          edge.hidden = true
        end
      end

      def self.create(model, o, world_transform, length = nil)
        resolved = Options.resolve(o.merge('length' => length || o['length']))
        data = Mesh.build(resolved)
        name = 'Noble Whitecard ' + Options.label(resolved)
        model.start_operation(name, true)
        started = true
        definition = model.definitions.add(name)
        group = model.active_entities.add_instance(definition, model.edit_transform.inverse * world_transform)
        group.name = name
        group.transformation = model.edit_transform.inverse * world_transform
        populate(group, data, resolved, model)
        model.commit_operation
        group
      rescue StandardError
        model.abort_operation if started
        raise
      end

      def self.update(model, group, o)
        raise ArgumentError, 'Select one unlocked Noble vegetation component or group in the current editing context.' unless vegetation?(group) && !group.locked? && model.active_entities.include?(group)
        o = Options.resolve(o)
        data = Mesh.build(o)
        model.start_operation('Edit Noble Whitecard Vegetation', true)
        started = true
        group.make_unique if group.definition.instances.length > 1
        DataSerializer.entities(group).clear!
        group.name = 'Noble Whitecard ' + Options.label(o) if group.name.start_with?('Noble Whitecard ')
        populate(group, data, o, model)
        model.commit_operation
        group
      rescue StandardError
        model.abort_operation if started
        raise
      end
    end
  end
end
