# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - MESH EXTRACTOR
# =============================================================================
#
# FILE       : Na__MeshDecimator__Decimation__MeshExtractor__.rb
# NAMESPACE  : Na__MeshDecimator::Na__Decimation::Na__MeshExtractor
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Extracts a triangulated, welded mesh data structure from a
#              SketchUp::Group.  Output is a plain Ruby Hash:
#
#              {
#                :vertices  => [ { :point => [x,y,z], :quadric => [...] }, ... ],
#                :triangles => [ { :vertices => [a,b,c], :material => obj }, ... ],
#                :stopped_early => false
#              }
#
#              Vertices sharing the same rounded key within weld_tolerance are
#              merged so downstream quadric collapse does not create seams.
#
# @delegate: 02__Geometry/Na__MeshDecimator__Geometry__VectorMath__.rb
# @delegate: 02__Geometry/Na__MeshDecimator__Geometry__QuadricMath__.rb
#
# =============================================================================

require 'sketchup.rb'

module Na__MeshDecimator
    module Na__Decimation
        module Na__MeshExtractor

            VectorMath  = Na__MeshDecimator::Na__Geometry::Na__VectorMath
            QuadricMath = Na__MeshDecimator::Na__Geometry::Na__QuadricMath

            EPSILON = Na__MeshDecimator::Na__Geometry::Na__QuadricMath::EPSILON

            # -----------------------------------------------------------------
            # REGION | Public Entry Point
            # -----------------------------------------------------------------

            def self.na_extract_triangulated_mesh(group, weld_tolerance_inches)
                group.make_unique if group.respond_to?(:make_unique)

                vertices         = []
                triangles        = []
                point_key_lookup = {}

                group.entities.grep(Sketchup::Face).each do |face|
                    material  = face.material || face.back_material
                    face_mesh = face.mesh

                    face_mesh.polygons.each do |polygon|
                        na_process_polygon(
                            polygon,
                            face_mesh,
                            material,
                            vertices,
                            triangles,
                            point_key_lookup,
                            weld_tolerance_inches
                        )
                    end
                end

                {
                    :vertices    => vertices,
                    :triangles   => triangles,
                    :stopped_early => false
                }
            end

            # -----------------------------------------------------------------
            # REGION | Polygon Processing
            # -----------------------------------------------------------------

            def self.na_process_polygon(polygon, face_mesh, material, vertices, triangles, point_key_lookup, weld_tolerance_inches)
                raw_indices = polygon.map { |i| i.abs }
                return if raw_indices.length < 3

                vertex_indices = raw_indices.map do |mesh_index|
                    point = face_mesh.point_at(mesh_index)
                    na_get_or_create_welded_vertex_index(vertices, point_key_lookup, point, weld_tolerance_inches)
                end

                if vertex_indices.length == 3
                    na_append_triangle_if_usable(triangles, vertex_indices[0], vertex_indices[1], vertex_indices[2], material, vertices)
                else
                    na_fan_triangulate_polygon(triangles, vertex_indices, material, vertices)
                end
            end
            private_class_method :na_process_polygon

            def self.na_fan_triangulate_polygon(triangles, vertex_indices, material, vertices)
                anchor = vertex_indices[0]
                (1...(vertex_indices.length - 1)).each do |i|
                    na_append_triangle_if_usable(triangles, anchor, vertex_indices[i], vertex_indices[i + 1], material, vertices)
                end
            end
            private_class_method :na_fan_triangulate_polygon

            # -----------------------------------------------------------------
            # REGION | Vertex Welding
            # -----------------------------------------------------------------

            def self.na_get_or_create_welded_vertex_index(vertices, point_key_lookup, point, tolerance)
                key = na_create_rounded_point_key(point, tolerance)

                existing = point_key_lookup[key]
                return existing if existing

                new_index = vertices.length
                vertices << {
                    :point   => [point.x.to_f, point.y.to_f, point.z.to_f],
                    :quadric => QuadricMath.na_create_zero_quadric
                }
                point_key_lookup[key] = new_index
                new_index
            end
            private_class_method :na_get_or_create_welded_vertex_index

            def self.na_create_rounded_point_key(point, tolerance)
                [
                    (point.x.to_f / tolerance).round,
                    (point.y.to_f / tolerance).round,
                    (point.z.to_f / tolerance).round
                ]
            end
            private_class_method :na_create_rounded_point_key

            # -----------------------------------------------------------------
            # REGION | Triangle Validation
            # -----------------------------------------------------------------

            def self.na_append_triangle_if_usable(triangles, a, b, c, material, vertices)
                return if a == b || b == c || c == a

                p0 = vertices[a][:point]
                p1 = vertices[b][:point]
                p2 = vertices[c][:point]

                return if VectorMath.na_triangle_area_twice(p0, p1, p2) <= EPSILON

                triangles << { :vertices => [a, b, c], :material => material }
            end
            private_class_method :na_append_triangle_if_usable

        end
    end
end
