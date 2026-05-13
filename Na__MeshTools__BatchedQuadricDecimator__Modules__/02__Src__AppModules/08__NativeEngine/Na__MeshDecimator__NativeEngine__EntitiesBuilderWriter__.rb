# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - NATIVE ENGINE WRITER
# =============================================================================
#
# FILE       : Na__MeshDecimator__NativeEngine__EntitiesBuilderWriter__.rb
# NAMESPACE  : Na__MeshDecimator::Na__NativeEngine::Na__EntitiesBuilderWriter
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : SketchUp 2026-friendly bulk geometry writer used by the native
#              decimation path. SketchUp API calls remain on Ruby's main thread.
#
# =============================================================================

require 'sketchup.rb'

module Na__MeshDecimator
    module Na__NativeEngine
        module Na__EntitiesBuilderWriter

            # -----------------------------------------------------------------
            # REGION | Geometry Write
            # -----------------------------------------------------------------

            def self.na_replace_group_geometry(group, simplified, options)
                entities = group.entities

                na_erase_existing_faces_and_edges(entities)

                written_faces = if entities.respond_to?(:build)
                    na_write_triangles_with_builder(entities, simplified[:vertices], simplified[:triangles])
                else
                    na_write_triangles_with_entities(entities, simplified[:vertices], simplified[:triangles])
                end

                na_smooth_edges(entities) if options[:smooth_rebuilt_edges]

                written_faces
            end

            # -----------------------------------------------------------------
            # REGION | Erase
            # -----------------------------------------------------------------

            def self.na_erase_existing_faces_and_edges(entities)
                erase_list = entities.to_a.select do |entity|
                    entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
                end

                entities.erase_entities(erase_list) unless erase_list.empty?
            end
            private_class_method :na_erase_existing_faces_and_edges

            # -----------------------------------------------------------------
            # REGION | Builder Write
            # -----------------------------------------------------------------

            def self.na_write_triangles_with_builder(entities, vertices, triangles)
                point_pool = na_build_point_pool(vertices)
                written    = 0

                entities.build do |builder|
                    triangles.each do |triangle|
                        points = na_triangle_points(point_pool, triangle)
                        face   = na_add_builder_face(builder, points)
                        next unless face

                        na_apply_triangle_material(face, triangle[:material])
                        written += 1
                    end
                end

                written
            end
            private_class_method :na_write_triangles_with_builder

            def self.na_add_builder_face(builder, points)
                builder.add_face(points)
            rescue StandardError
                begin
                    builder.add_face(points.reverse)
                rescue StandardError
                    nil
                end
            end
            private_class_method :na_add_builder_face

            def self.na_build_point_pool(vertices)
                vertices.map do |vertex|
                    raw = vertex[:point]
                    Geom::Point3d.new(raw[0], raw[1], raw[2])
                end
            end
            private_class_method :na_build_point_pool

            def self.na_triangle_points(point_pool, triangle)
                triangle[:vertices].map { |index| point_pool[index] }
            end
            private_class_method :na_triangle_points

            # -----------------------------------------------------------------
            # REGION | Fallback Write
            # -----------------------------------------------------------------

            def self.na_write_triangles_with_entities(entities, vertices, triangles)
                written = 0

                triangles.each do |triangle|
                    points = triangle[:vertices].map do |index|
                        raw = vertices[index][:point]
                        Geom::Point3d.new(raw[0], raw[1], raw[2])
                    end

                    face = entities.add_face(points[0], points[1], points[2])
                    face ||= entities.add_face(points[2], points[1], points[0])
                    next unless face

                    na_apply_triangle_material(face, triangle[:material])
                    written += 1
                end

                written
            end
            private_class_method :na_write_triangles_with_entities

            # -----------------------------------------------------------------
            # REGION | Materials & Edge Smoothing
            # -----------------------------------------------------------------

            def self.na_apply_triangle_material(face, material)
                return unless material

                face.material      = material
                face.back_material = material
            end
            private_class_method :na_apply_triangle_material

            def self.na_smooth_edges(entities)
                entities.grep(Sketchup::Edge).each do |edge|
                    edge.soft   = true
                    edge.smooth = true
                end
            end
            private_class_method :na_smooth_edges

        end
    end
end
