# =============================================================================
# NA ARRAY BUILDER TOOLS - PREVIEW GEOMETRY
# FILE       : Na__ArrayBuilder__PreviewGeometry__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Cache real source meshes and instance them without model changes.
# =============================================================================

require_relative 'Na__ArrayBuilder__LayoutEngine__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__PreviewGeometry

        NA_TRIANGLE_BUDGET = 120_000
        NA_PANEL_BUDGET = 30_000
        NA_SOURCE_LIMIT = 250_000
        NA_BLOCK_FACES = [[0,3,2,1], [4,5,6,7], [0,1,5,4], [1,2,6,5], [2,3,7,6], [3,0,4,7]].freeze
        NA_BLOCK_EDGES = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]].freeze

        def self.Na__Preview__Clear
            @na_key = @na_mesh = nil
        end

        # FUNCTION | Read a Closed Source Definition Once per Geometry Revision
        # ------------------------------------------------------------
        def self.Na__Preview__Mesh(na_plan)
            na_source = na_plan[:source]
            return Na__Preview__Block(na_plan[:config]) unless na_source
            na_definition = na_source[:definition]
            na_key = [na_definition, na_definition.guid]
            return @na_mesh if @na_key == na_key && @na_mesh
            na_mesh = { points: [], triangles: [], edges: [] }
            Na__Preview__Collect(na_definition, Geom::Transformation.new, nil, na_mesh, [])
            @na_key, @na_mesh = na_key, na_mesh
            na_mesh
        end

        # FUNCTION | Multiply CLOSED Child Transforms Exactly Once, Parent First
        # ------------------------------------------------------------
        def self.Na__Preview__Collect(na_definition, na_transform, na_material, na_mesh, na_stack)
            return if na_stack.include?(na_definition)
            raise ArgumentError, 'The source nesting is too deep to preview.' if na_stack.length >= 64
            na_definition.entities.each do |na_entity|
                next if na_entity.hidden? || !na_entity.layer.visible?
                na_colour_material = na_entity.material || na_material
                if na_entity.is_a?(Sketchup::Face)
                    Na__Preview__Face(na_entity, na_transform, na_colour_material, na_mesh)
                elsif na_entity.is_a?(Sketchup::Edge)
                    next if na_entity.soft? || na_entity.smooth?
                    na_indices = [na_entity.start.position, na_entity.end.position].map do |na_point|
                        na_mesh[:points] << na_point.transform(na_transform)
                        na_mesh[:points].length - 1
                    end
                    na_mesh[:edges] << na_indices
                elsif na_entity.is_a?(Sketchup::Group) || na_entity.is_a?(Sketchup::ComponentInstance)
                    Na__Preview__Collect(na_entity.definition, na_transform * na_entity.transformation,
                        na_colour_material, na_mesh, na_stack + [na_definition])
                end
                if na_mesh[:triangles].length + na_mesh[:edges].length > NA_SOURCE_LIMIT
                    raise ArgumentError, 'This source exceeds the preview mesh budget. The array can still be built.'
                end
            end
        end

        def self.Na__Preview__Face(na_face, na_transform, na_material, na_mesh)
            na_polygon_mesh = na_face.mesh(0)
            na_offset = na_mesh[:points].length
            na_polygon_mesh.points.each { |na_point| na_mesh[:points] << na_point.transform(na_transform) }
            na_colour = na_material ? na_material.color : nil
            na_rgb = na_colour ? [na_colour.red, na_colour.green, na_colour.blue] : [121, 167, 216]
            na_polygon_mesh.polygons.each do |na_polygon|
                na_indices = na_polygon.map { |na_index| na_offset + na_index.abs - 1 }
                (1...na_indices.length - 1).each do |na_index|
                    na_mesh[:triangles] << [na_indices[0], na_indices[na_index], na_indices[na_index + 1], na_rgb]
                end
            end
        end

        def self.Na__Preview__Block(na_config)
            na_position = { point: ORIGIN, direction: X_AXIS }
            na_config = na_config.merge('offset_lateral_mm' => 0, 'offset_vertical_mm' => 0)
            na_points = Na__ArrayBuilder__LayoutEngine.Na__Layout__Corners(na_position, na_config)
            na_triangles = NA_BLOCK_FACES.flat_map { |na_a, na_b, na_c, na_d|
                [[na_a, na_b, na_c, [121,167,216]], [na_a, na_c, na_d, [121,167,216]]]
            }
            { points: na_points, triangles: na_triangles, edges: NA_BLOCK_EDGES }
        end

        # FUNCTION | Build Instanced Preview Data with a Bounded Drawing Cost
        # ------------------------------------------------------------
        def self.Na__Preview__Resolve(na_plan)
            na_mesh = Na__Preview__Mesh(na_plan)
            na_cost = [na_mesh[:triangles].length + na_mesh[:edges].length, 1].max
            na_count = [[NA_TRIANGLE_BUDGET / na_cost, 1].max, na_plan[:positions].length].min
            na_transforms = na_plan[:positions].first(na_count).map { |na_position|
                Na__ArrayBuilder__LayoutEngine.Na__Layout__Transform(na_position, na_plan[:config], na_plan[:source])
            }
            { mesh: na_mesh, transforms: na_transforms,
              panel_count: [[NA_PANEL_BUDGET / na_cost, 1].max, na_count, 400].min,
              total_count: na_plan[:positions].length }
        end

        def self.Na__Preview__Payload(na_geometry, na_plan)
            na_mesh = na_geometry[:mesh]
            na_count = na_geometry[:panel_count]
            {
                'mesh' => { 'points' => na_mesh[:points].map(&:to_a), 'triangles' => na_mesh[:triangles], 'edges' => na_mesh[:edges] },
                'instances' => na_geometry[:transforms].first(na_count).map(&:to_a),
                'path' => na_plan[:points].map(&:to_a), 'preview_count' => na_count,
                'truncated' => na_count < na_geometry[:total_count]
            }
        end

        # FUNCTION | Cache World-Space Draw Batches Outside the Tool Draw Callback
        # ------------------------------------------------------------
        def self.Na__Preview__DrawBatches(na_geometry, na_frame)
            na_mesh = na_geometry[:mesh]
            na_faces, na_edges = {}, []
            na_geometry[:transforms].each do |na_transform|
                na_transform = na_frame * na_transform
                na_points = na_mesh[:points].map { |na_point| na_point.transform(na_transform) }
                na_mesh[:triangles].each do |na_a, na_b, na_c, na_rgb|
                    (na_faces[na_rgb] ||= []).concat([na_points[na_a], na_points[na_b], na_points[na_c]])
                end
                na_mesh[:edges].each { |na_a, na_b| na_edges.concat([na_points[na_a], na_points[na_b]]) }
            end
            { faces: na_faces, edges: na_edges, count: na_geometry[:transforms].length }
        end

    end # module Na__ArrayBuilder__PreviewGeometry
end # module Na__ArrayBuilderTools
