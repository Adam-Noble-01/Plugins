# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - MESH WRITER
# =============================================================================
#
# FILE       : Na__MeshDecimator__Decimation__MeshWriter__.rb
# NAMESPACE  : Na__MeshDecimator::Na__Decimation::Na__MeshWriter
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Replaces the face and edge geometry inside a SketchUp::Group
#              with the simplified triangle set produced by the decimation
#              pipeline.  Returns the count of faces successfully written.
#
# =============================================================================

require 'sketchup.rb'

module Na__MeshDecimator
    module Na__Decimation
        module Na__MeshWriter

            # -----------------------------------------------------------------
            # REGION | Geometry Write
            # -----------------------------------------------------------------

            # Erases all faces and edges in the group then writes the
            # simplified triangles back.  Applies original materials where
            # present.  Optionally smooths all rebuilt edges.
            #
            # @param group    [Sketchup::Group]
            # @param simplified [Hash]  mesh_data hash from the simplifier
            # @param options  [Hash]   must include :smooth_rebuilt_edges
            # @return [Integer] number of faces written
            def self.na_replace_group_geometry(group, simplified, options)
                entities = group.entities

                na_erase_existing_faces_and_edges(entities)

                written_faces = na_write_triangles(entities, simplified[:vertices], simplified[:triangles])

                na_smooth_edges(entities) if options[:smooth_rebuilt_edges]

                written_faces
            end

            # -----------------------------------------------------------------
            # REGION | Erase
            # -----------------------------------------------------------------

            def self.na_erase_existing_faces_and_edges(entities)
                erase_list = entities.to_a.select do |e|
                    e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge)
                end
                entities.erase_entities(erase_list) unless erase_list.empty?
            end
            private_class_method :na_erase_existing_faces_and_edges

            # -----------------------------------------------------------------
            # REGION | Write Triangles
            # -----------------------------------------------------------------

            def self.na_write_triangles(entities, vertices, triangles)
                written = 0

                triangles.each do |triangle|
                    points = triangle[:vertices].map do |index|
                        raw = vertices[index][:point]
                        Geom::Point3d.new(raw[0], raw[1], raw[2])
                    end

                    face = entities.add_face(points[0], points[1], points[2])
                    face ||= entities.add_face(points[2], points[1], points[0])
                    next unless face

                    if triangle[:material]
                        face.material      = triangle[:material]
                        face.back_material = triangle[:material]
                    end

                    written += 1
                end

                written
            end
            private_class_method :na_write_triangles

            # -----------------------------------------------------------------
            # REGION | Edge Smoothing
            # -----------------------------------------------------------------

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
