# =============================================================================
# NA PROFILE TOOLS - CREATE NEW PROFILE - EXPORTER
# =============================================================================
#
# FILE       : Na__ProfileTools__CreateNewProfile__Exporter__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__ProfileExporter
# PURPOSE    : Export selected profile geometry to the unified Na__ schema.
#              Edge colour data is now resolved through Na__EdgeColourManager.
#
# =============================================================================

require 'json'
require 'time'

module Na__ProfileTools__ProfilePathTracer
    module Na__ProfileExporter

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_MM_PER_INCH = 25.4
        NA_TOLERANCE_MM = 0.0001

        NA_DATA_FILES_DIR = File.expand_path(
            '../../04__Data__ProfileLibrary',
            File.dirname(__FILE__)
        ).freeze

        NA_ORIGIN_HELPER_GROUP_NAME = '00__OriginPoint'.freeze
        NA_ORIGIN_HELPER_TAG_NAME = '00__OriginPoint'.freeze
        NA_ORIGIN_HELPER_COLOUR_ID = 'MTE201__LineColour__Red'.freeze
        NA_ORIGIN_HELPER_SIZE_MM = 120.0

        NA_DEFAULT_EDGE_HEX = '#666666'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Selection Validation
    # -------------------------------------------------------------------------

        def self.Na__Exporter__ValidateSelection(origin_point = nil)
            model = Sketchup.active_model
            return { 'isValid' => false, 'reason' => 'No active model.' } unless model

            selection = model.selection.to_a
            return { 'isValid' => false, 'reason' => 'Nothing is selected.' } if selection.empty?

            faces = []
            edges = []
            self.Na__Exporter__CollectEntitiesFromSelection(selection, faces, edges)

            if faces.empty? && edges.empty?
                return { 'isValid' => false, 'reason' => 'Selection contains no faces or edges.' }
            end

            if self.Na__Exporter__CountUniqueVertices(faces, edges) < 3
                return { 'isValid' => false, 'reason' => 'Selection must contain at least three unique vertices.' }
            end

            {
                'isValid' => true,
                'reason' => nil,
                'faceCount' => faces.length,
                'edgeCount' => edges.length,
                'vertexCount' => self.Na__Exporter__CountUniqueVertices(faces, edges),
                'previewPoints' => self.Na__Exporter__ExtractPreviewPoints(faces, edges, origin_point)
            }
        end

        def self.Na__Exporter__ExtractPreviewPoints(faces, edges, origin_point = nil)
            if origin_point
                frame = self.Na__Exporter__BuildLocalFrame(faces, edges, origin_point)
                if faces.any?
                    face = faces.first
                    return face.outer_loop.vertices.map do |vertex|
                        y_mm, z_mm = self.Na__Exporter__ProjectPointToLocalYZ(vertex.position, frame)
                        [y_mm, z_mm]
                    end
                end

                return edges.flat_map { |edge| [edge.start, edge.end] }
                            .uniq { |vertex| vertex.persistent_id }
                            .map do |vertex|
                    y_mm, z_mm = self.Na__Exporter__ProjectPointToLocalYZ(vertex.position, frame)
                    [y_mm, z_mm]
                end
            end

            if faces.any?
                face = faces.first
                return face.outer_loop.vertices.map do |vertex|
                    pos = vertex.position
                    [(pos.x.to_f * NA_MM_PER_INCH).round(6), (pos.y.to_f * NA_MM_PER_INCH).round(6)]
                end
            end

            edges.flat_map { |edge| [edge.start, edge.end] }
                 .uniq { |vertex| vertex.persistent_id }
                 .map do |vertex|
                pos = vertex.position
                [(pos.x.to_f * NA_MM_PER_INCH).round(6), (pos.y.to_f * NA_MM_PER_INCH).round(6)]
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Export Workflow
    # -------------------------------------------------------------------------

        def self.Na__Exporter__RunExport(meta_fields, origin_point = nil)
            helper_result = self.Na__Exporter__CreateOriginHelperAtPoint(origin_point)

            geometry_data = self.Na__Exporter__CollectGeometry(origin_point)
            unless geometry_data
                return {
                    'isSaved' => false,
                    'reason' => 'No geometry collected from selection.',
                    'originHelperCreated' => helper_result['isCreated'] == true,
                    'originHelperReason' => helper_result['reason'],
                    'originHelperName' => helper_result['groupName']
                }
            end

            json_data = self.Na__Exporter__BuildJsonPayload(geometry_data, meta_fields || {})
            suggested_name = (json_data.dig('Na__Asset__Metadata', 'Na__Asset__Code') || '').to_s
            suggested_name = (json_data.dig('Na__Asset__Metadata', 'Na__Asset__Name') || '').to_s if suggested_name.strip.empty?

            save_result = self.Na__Exporter__PromptAndSave(json_data, suggested_name)
            save_result.merge(
                'originHelperCreated' => helper_result['isCreated'] == true,
                'originHelperReason' => helper_result['reason'],
                'originHelperName' => helper_result['groupName']
            )
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Entity Collection
    # -------------------------------------------------------------------------

        def self.Na__Exporter__CollectEntitiesFromSelection(entities, faces, edges)
            seen_faces = {}
            seen_edges = {}

            Array(entities).each do |entity|
                case entity
                when Sketchup::Face
                    next if seen_faces[entity.persistent_id]
                    seen_faces[entity.persistent_id] = true
                    faces << entity
                    entity.edges.each do |edge|
                        next if seen_edges[edge.persistent_id]
                        seen_edges[edge.persistent_id] = true
                        edges << edge
                    end
                when Sketchup::Edge
                    next if seen_edges[entity.persistent_id]
                    seen_edges[entity.persistent_id] = true
                    edges << entity
                when Sketchup::Group
                    self.Na__Exporter__CollectEntitiesFromSelection(entity.entities.to_a, faces, edges)
                when Sketchup::ComponentInstance
                    self.Na__Exporter__CollectEntitiesFromSelection(entity.definition.entities.to_a, faces, edges)
                end
            end
        end

        def self.Na__Exporter__CountUniqueVertices(faces, edges)
            vertex_ids = {}
            faces.each { |face| face.vertices.each { |vertex| vertex_ids[vertex.persistent_id] = true } }
            edges.each { |edge| [edge.start, edge.end].each { |vertex| vertex_ids[vertex.persistent_id] = true } }
            vertex_ids.length
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Geometry Collection (Selection -> Unified Blocks)
    # -------------------------------------------------------------------------

        def self.Na__Exporter__CollectGeometry(origin_point)
            model = Sketchup.active_model
            return nil unless model

            selection = model.selection.to_a
            return nil if selection.empty?

            faces = []
            edges = []
            self.Na__Exporter__CollectEntitiesFromSelection(selection, faces, edges)
            return nil if faces.empty? && edges.empty?

            export_origin = origin_point || self.Na__Exporter__DetermineFallbackOrigin(faces, edges)
            frame = self.Na__Exporter__BuildLocalFrame(faces, edges, export_origin)

            vertex_lookup = {}
            profile_vertices = []
            profile_edges = []
            mesh_edges = []

            seen_pairs = {}
            edge_index = 0

            edges.each do |edge|
                start_vertex_id = self.Na__Exporter__IndexProjectedPoint(edge.start.position, frame, vertex_lookup, profile_vertices)
                end_vertex_id = self.Na__Exporter__IndexProjectedPoint(edge.end.position, frame, vertex_lookup, profile_vertices)
                next unless start_vertex_id && end_vertex_id
                next if start_vertex_id == end_vertex_id

                pair_key = [start_vertex_id, end_vertex_id].sort.join('|')
                next if seen_pairs[pair_key]
                seen_pairs[pair_key] = true

                edge_index += 1
                edge_id = format('E%03d', edge_index)
                profile_edges << {
                    'EdgeId' => edge_id,
                    'StartVertex' => start_vertex_id,
                    'EndVertex' => end_vertex_id
                }
                mesh_edges << self.Na__Exporter__BuildMeshEdgeRecord(edge, edge_id, start_vertex_id, end_vertex_id)
            end

            profile_faces = self.Na__Exporter__BuildProfileFaceRecords(faces, frame, vertex_lookup, profile_vertices)
            if profile_faces.empty?
                fallback_face = self.Na__Exporter__BuildFallbackFaceRecord(profile_edges)
                profile_faces << fallback_face if fallback_face
            end

            return nil if profile_vertices.empty? || profile_edges.empty? || profile_faces.empty?

            mesh_vertices = self.Na__Exporter__BuildMeshVertices(profile_vertices)
            mesh_faces = self.Na__Exporter__BuildMeshFaces(profile_faces)
            mesh_bbox = self.Na__Exporter__BuildMeshBoundingBox(mesh_vertices)

            {
                'originPoint' => export_origin,
                'frame' => frame,
                'profileVertices' => profile_vertices,
                'profileEdges' => profile_edges,
                'profileFaces' => profile_faces,
                'meshVertices' => mesh_vertices,
                'meshEdges' => mesh_edges,
                'meshFaces' => mesh_faces,
                'meshBoundingBox' => mesh_bbox
            }
        end

        def self.Na__Exporter__DetermineFallbackOrigin(faces, edges)
            return edges.first.start.position if edges.any?
            return faces.first.outer_loop.vertices.first.position if faces.any?
            Geom::Point3d.new(0, 0, 0)
        end

        def self.Na__Exporter__BuildLocalFrame(faces, edges, origin_point)
            normal = self.Na__Exporter__DeriveFaceNormal(faces, edges)
            normal = Z_AXIS.clone if normal.length <= 0.001
            normal.normalize!

            world_up = normal.parallel?(Z_AXIS) ? Y_AXIS.clone : Z_AXIS.clone
            axis_z = self.Na__Exporter__ProjectVectorOntoPlane(world_up, normal)
            axis_z = Y_AXIS.clone if axis_z.length <= 0.001
            axis_z.normalize!

            axis_y = normal * axis_z
            axis_y = X_AXIS.clone if axis_y.length <= 0.001
            axis_y.normalize!

            {
                origin: origin_point,
                axis_y: axis_y,
                axis_z: axis_z
            }
        end

        def self.Na__Exporter__DeriveFaceNormal(faces, edges)
            if faces.any?
                face_normal = faces.first.normal
                return face_normal if face_normal.length > 0.001
            end

            if edges.any?
                longest_edge_vector = self.Na__Exporter__FindLongestEdgeVector(edges)
                if longest_edge_vector && longest_edge_vector.length > 0.001
                    world_up = longest_edge_vector.parallel?(Z_AXIS) ? Y_AXIS.clone : Z_AXIS.clone
                    implied_normal = longest_edge_vector * world_up
                    return implied_normal if implied_normal.length > 0.001
                end
            end

            Z_AXIS.clone
        end

        def self.Na__Exporter__FindLongestEdgeVector(edges)
            longest_vector = nil
            longest_length = 0.0

            edges.each do |edge|
                candidate = edge.end.position - edge.start.position
                next unless candidate.length > longest_length
                longest_vector = candidate
                longest_length = candidate.length
            end

            longest_vector
        end

        def self.Na__Exporter__ProjectVectorOntoPlane(vector, plane_normal)
            dot_value = vector.dot(plane_normal)
            Geom::Vector3d.new(
                vector.x - plane_normal.x * dot_value,
                vector.y - plane_normal.y * dot_value,
                vector.z - plane_normal.z * dot_value
            )
        end

        def self.Na__Exporter__IndexProjectedPoint(point, frame, vertex_lookup, profile_vertices)
            y_mm, z_mm = self.Na__Exporter__ProjectPointToLocalYZ(point, frame)
            quant_key = self.Na__Exporter__QuantKey(y_mm, z_mm)
            return vertex_lookup[quant_key] if vertex_lookup.key?(quant_key)

            vertex_id = format('V%03d', profile_vertices.length + 1)
            profile_vertices << {
                'VertexId' => vertex_id,
                'PosY_mm' => y_mm,
                'PosZ_mm' => z_mm
            }
            vertex_lookup[quant_key] = vertex_id
            vertex_id
        end

        def self.Na__Exporter__ProjectPointToLocalYZ(point, frame)
            delta = point - frame[:origin]
            y_mm = (delta.dot(frame[:axis_y]) * NA_MM_PER_INCH).round(6)
            z_mm = (delta.dot(frame[:axis_z]) * NA_MM_PER_INCH).round(6)
            [y_mm, z_mm]
        end

        def self.Na__Exporter__QuantKey(y_mm, z_mm)
            y_quant = (y_mm / NA_TOLERANCE_MM).round
            z_quant = (z_mm / NA_TOLERANCE_MM).round
            "#{y_quant}|#{z_quant}"
        end

        def self.Na__Exporter__BuildProfileFaceRecords(faces, frame, vertex_lookup, profile_vertices)
            face_records = []
            face_counter = 0

            faces.each do |face|
                outer_loop_ids = self.Na__Exporter__LoopVertexIds(face.outer_loop, frame, vertex_lookup, profile_vertices)
                next if outer_loop_ids.length < 3

                face_counter += 1
                face_records << {
                    'FaceId' => format('F%03d', face_counter),
                    'OuterLoopVertices' => outer_loop_ids
                }
            end

            face_records
        end

        def self.Na__Exporter__LoopVertexIds(loop, frame, vertex_lookup, profile_vertices)
            loop.vertices.map do |vertex|
                self.Na__Exporter__IndexProjectedPoint(vertex.position, frame, vertex_lookup, profile_vertices)
            end.compact
        end

        def self.Na__Exporter__BuildFallbackFaceRecord(profile_edges)
            ids = []
            profile_edges.each do |edge|
                ids << edge['StartVertex']
                ids << edge['EndVertex']
            end
            loop_ids = ids.uniq
            return nil if loop_ids.length < 3

            {
                'FaceId' => 'F001',
                'OuterLoopVertices' => loop_ids
            }
        end

        def self.Na__Exporter__BuildMeshVertices(profile_vertices)
            profile_vertices.map do |vertex|
                vertex_id = vertex['VertexId']
                y_mm = vertex['PosY_mm'].to_f
                z_mm = vertex['PosZ_mm'].to_f
                {
                    'VertexId' => vertex_id,
                    'VertexName' => "Na__ProfileMesh__Vertex__#{vertex_id}",
                    'PosX_mm' => y_mm,
                    'PosY_mm' => z_mm,
                    'PosZ_mm' => 0.0,
                    'Normal_X' => 0.0,
                    'Normal_Y' => 0.0,
                    'Normal_Z' => 1.0
                }
            end
        end

        def self.Na__Exporter__BuildMeshFaces(profile_faces)
            profile_faces.map do |face|
                face_id = face['FaceId']
                {
                    'FaceId' => face_id,
                    'FaceName' => "Na__ProfileMesh__Face__#{face_id}",
                    'OuterLoop_VertexIds' => face['OuterLoopVertices'],
                    'InnerLoops' => [],
                    'Normal' => [0.0, 0.0, 1.0],
                    'Area_mm2' => nil,
                    'MaterialName' => ''
                }
            end
        end

        def self.Na__Exporter__BuildMeshBoundingBox(mesh_vertices)
            return {} if mesh_vertices.empty?

            xs = mesh_vertices.map { |vertex| vertex['PosX_mm'].to_f }
            ys = mesh_vertices.map { |vertex| vertex['PosY_mm'].to_f }
            zs = mesh_vertices.map { |vertex| vertex['PosZ_mm'].to_f }

            {
                'Na__Geometry__MinX_mm' => xs.min.round(6),
                'Na__Geometry__MaxX_mm' => xs.max.round(6),
                'Na__Geometry__MinY_mm' => ys.min.round(6),
                'Na__Geometry__MaxY_mm' => ys.max.round(6),
                'Na__Geometry__MinZ_mm' => zs.min.round(6),
                'Na__Geometry__MaxZ_mm' => zs.max.round(6)
            }
        end

        def self.Na__Exporter__BuildMeshEdgeRecord(edge, edge_id, start_vertex_id, end_vertex_id)
            model = Sketchup.active_model
            material_name = edge.material ? edge.material.display_name.to_s : ''

            if defined?(Na__EdgeColourManager) && Na__EdgeColourManager.respond_to?(:Na__EdgeColours__IsStandardName?)
                canonical = Na__EdgeColourManager.Na__EdgeColours__CanonicalIdForMaterial(material_name, edge)
                if canonical
                    material_name = canonical
                    colour_id = canonical
                    entry = Na__EdgeColourManager.Na__EdgeColours__GetEntryByName(canonical)
                    colour_hex = entry ? entry['HexValue'].to_s : self.Na__Exporter__RgbToHexFromEdge(edge)
                else
                    colour_id = self.Na__Exporter__ResolveEdgeColourId(material_name)
                    colour_hex = self.Na__Exporter__ResolveEdgeColourHexFallback(edge, colour_id)
                end
            else
                colour_id = self.Na__Exporter__ResolveEdgeColourId(material_name)
                colour_hex = self.Na__Exporter__ResolveEdgeColourHexFallback(edge, colour_id)
            end

            {
                'EdgeId' => edge_id,
                'StartVertex' => start_vertex_id,
                'EndVertex' => end_vertex_id,
                'IsSoft' => edge.soft? == true,
                'IsSmooth' => edge.smooth? == true,
                'IsHidden' => edge.hidden? == true,
                'CastsShadows' => edge.respond_to?(:casts_shadows?) ? (edge.casts_shadows? == true) : true,
                'EdgeMaterialName' => material_name,
                'EdgeColourId' => colour_id.to_s,
                'EdgeColourHex' => colour_hex.to_s
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Unified JSON Payload Builder
    # -------------------------------------------------------------------------

        def self.Na__Exporter__BuildJsonPayload(geometry_data, meta_fields)
            timestamp = Time.now.getlocal.strftime('%d-%b-%Y__%H:%M')
            profile_name = meta_fields['Meta_ProfileName'].to_s.strip
            profile_name = 'Na Profile' if profile_name.empty?

            profile_code = meta_fields['Meta_ProfileId'].to_s.strip
            profile_code = profile_name.gsub(/[^\w\-.]+/, '__') if profile_code.empty?

            # Optional. Left empty rather than seeded from the name: an alias
            # that duplicates the full name is worse than none, because the
            # Gallery then shows the long string and believes it was chosen.
            profile_short_name = meta_fields['Meta_ProfileShortName'].to_s.strip

            profile_description = meta_fields['Meta_Description'].to_s
            profile_keywords = Array(meta_fields['Meta_Keywords'])

            {
                'meta' => {
                    'fileName' => "#{profile_code}.json",
                    'description' => 'Profile exported by Na__ProfileTools__ProfilePathTracer.',
                    'version' => '1.0.0',
                    'lastUpdated' => Time.now.strftime('%d-%b-%Y'),
                    'namingConvention' => 'All custom keys use Na__ prefixed three-stage naming.',
                    'fieldPrefixes' => {
                        'Na__Asset__' => 'Top-level asset metadata and content blocks',
                        'Na__Geometry__' => 'Geometry fields and coordinate metadata',
                        'Na__PanelPlacement__' => 'Reserved placement metadata'
                    },
                    'Meta_ProfileTimestamp' => timestamp,
                    'Meta_ProfileShortName' => profile_short_name,
                    'Meta_ProfileKeywords' => profile_keywords
                },
                'Na__Asset__Metadata' => {
                    'Na__Asset__Name' => profile_name,
                    'Na__Asset__ShortName' => profile_short_name,
                    'Na__Asset__Code' => profile_code,
                    'Na__Asset__Type' => 'Profile2D',
                    'Na__Asset__Description' => profile_description,
                    'Na__Asset__Notes' => 'Generated by Na__ProfileTools__ProfilePathTracer.',
                    'Na__Asset__Has2dPlan' => false,
                    'Na__Asset__Has2dElevation' => false,
                    'Na__Asset__Has2dProfile' => true,
                    'Na__Asset__Has3d' => true,
                    'Na__Asset__Supplier' => '',
                    'Na__Asset__SupplierProductCode' => '',
                    'Na__Asset__SupplierPrice_GBP' => '',
                    'Na__PanelPlacement__DefaultHeight_mm' => nil,
                    'Na__PanelPlacement__RightHand' => {
                        'Na__PanelPlacement__OffsetX_mm' => nil,
                        'Na__PanelPlacement__OffsetY_mm' => nil,
                        'Na__PanelPlacement__ScaleX' => nil
                    },
                    'Na__PanelPlacement__LeftHand' => {
                        'Na__PanelPlacement__OffsetX_mm' => nil,
                        'Na__PanelPlacement__OffsetY_mm' => nil,
                        'Na__PanelPlacement__ScaleX' => nil
                    },
                    'Na__Asset__AvailableFinishes' => []
                }
            }.merge(self.Na__Exporter__BuildGeometryBlocks(geometry_data))
        end

        # Split out from the payload builder so the Edit Profile geometry
        # re-capture writes byte-identical geometry blocks into an existing file.
        # Two copies of this shape would drift the moment either side changed.
        def self.Na__Exporter__BuildGeometryBlocks(geometry_data)
            mesh_edges = geometry_data['meshEdges'] || []
            soft_count = mesh_edges.count { |edge| edge['IsSoft'] == true }
            smooth_count = mesh_edges.count { |edge| edge['IsSmooth'] == true }
            hard_count = mesh_edges.count { |edge| edge['IsSoft'] != true && edge['IsSmooth'] != true }

            {
                'Na__Asset__Profile2D' => {
                    'Na__Geometry__OriginNote' => 'Local 0,0 = clicked 00__OriginPoint helper location.',
                    'Na__Geometry__CoordSystem' => 'Y=profile horizontal axis, Z=profile vertical axis | Units=mm',
                    'Na__Geometry__Vertices' => geometry_data['profileVertices'],
                    'Na__Geometry__Edges' => geometry_data['profileEdges'],
                    'Na__Geometry__Faces' => geometry_data['profileFaces']
                },
                'Na__Asset__Mesh3D' => {
                    'Na__Geometry__OriginNote' => 'Local 0,0,0 = clicked 00__OriginPoint helper location.',
                    'Na__Geometry__CoordSystem' => 'Right-handed | X=profile-width surrogate, Y=profile-height surrogate, Z=0 | Units=mm',
                    'Na__Geometry__BoundingBox' => geometry_data['meshBoundingBox'],
                    'Na__Geometry__Counts' => {
                        'Na__Geometry__VertexCount' => (geometry_data['meshVertices'] || []).length,
                        'Na__Geometry__FaceCount' => (geometry_data['meshFaces'] || []).length,
                        'Na__Geometry__EdgeCount' => mesh_edges.length,
                        'Na__Geometry__HardEdgeCount' => hard_count,
                        'Na__Geometry__SoftEdgeCount' => soft_count,
                        'Na__Geometry__SmoothEdgeCount' => smooth_count
                    },
                    'Na__Geometry__Vertices' => geometry_data['meshVertices'],
                    'Na__Geometry__Faces' => geometry_data['meshFaces'],
                    'Na__Geometry__Edges' => mesh_edges
                }
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | File Save
    # -------------------------------------------------------------------------

        def self.Na__Exporter__PromptAndSave(json_data, suggested_filename)
            default_dir = NA_DATA_FILES_DIR
            Dir.mkdir(default_dir) unless File.directory?(default_dir)

            safe_name = suggested_filename.to_s.gsub(/[^\w\-\.\(\) ]+/, '_')
            safe_name = 'Na__NewProfile__Data' if safe_name.strip.empty?
            safe_name += '.json' unless safe_name.end_with?('.json')

            path = UI.savepanel('Save Profile Data File', default_dir, safe_name)
            return { 'isSaved' => false, 'reason' => 'Save cancelled by user.' } unless path

            path += '.json' unless path.end_with?('.json')

            json_state = JSON::State.new(
                indent: '  ',
                space: '  ',
                space_before: '  ',
                object_nl: "\n",
                array_nl: "\n"
            )

            File.open(path, 'w:utf-8') { |file| file.write(JSON.generate(json_data, json_state)) }
            { 'isSaved' => true, 'filePath' => path, 'reason' => nil }
        rescue => error
            { 'isSaved' => false, 'reason' => "Save failed: #{error.message}" }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Origin Helper Creation
    # -------------------------------------------------------------------------

        def self.Na__Exporter__CreateOriginHelperAtPoint(origin_point)
            return { 'isCreated' => false, 'reason' => 'No origin point was supplied.' } unless origin_point

            model = Sketchup.active_model
            return { 'isCreated' => false, 'reason' => 'No active model.' } unless model

            model.start_operation('Na__ProfilePathTracer__CreateOriginHelper', true)

            group = model.active_entities.add_group
            group.name = NA_ORIGIN_HELPER_GROUP_NAME
            entities = group.entities
            size = NA_ORIGIN_HELPER_SIZE_MM.mm

            centre = origin_point
            entities.add_line(centre, Geom::Point3d.new(centre.x + size, centre.y, centre.z))
            entities.add_line(centre, Geom::Point3d.new(centre.x - size, centre.y, centre.z))
            entities.add_line(centre, Geom::Point3d.new(centre.x, centre.y + size, centre.z))
            entities.add_line(centre, Geom::Point3d.new(centre.x, centre.y - size, centre.z))
            entities.add_line(centre, Geom::Point3d.new(centre.x, centre.y, centre.z + size))
            entities.add_line(centre, Geom::Point3d.new(centre.x, centre.y, centre.z - size))

            helper_tag = self.Na__Exporter__EnsureOriginHelperTag(model)
            group.layer = helper_tag if helper_tag

            helper_material = self.Na__Exporter__EnsureOriginHelperMaterial(model)
            if helper_material
                entities.grep(Sketchup::Edge).each { |edge| edge.material = helper_material }
            end

            model.commit_operation
            {
                'isCreated' => true,
                'reason' => nil,
                'groupName' => group.name
            }
        rescue => error
            model.abort_operation if model
            {
                'isCreated' => false,
                'reason' => "Origin helper creation failed: #{error.message}"
            }
        end

        def self.Na__Exporter__EnsureOriginHelperTag(model)
            layer = model.layers[NA_ORIGIN_HELPER_TAG_NAME] || model.layers.add(NA_ORIGIN_HELPER_TAG_NAME)
            layer.visible = true if layer.respond_to?(:visible=)
            tag_entry = self.Na__Exporter__FindTagEntryByName(NA_ORIGIN_HELPER_TAG_NAME)

            if tag_entry && tag_entry['Layout__EdgeColourRGB'].is_a?(Array) && tag_entry['Layout__EdgeColourRGB'].length == 3
                rgb = tag_entry['Layout__EdgeColourRGB'].map(&:to_i)
                layer.color = Sketchup::Color.new(*rgb) if layer.respond_to?(:color=)
            end

            line_style_name = tag_entry ? tag_entry['Layout__LineStyleName'].to_s : ''
            if !line_style_name.empty? && layer.respond_to?(:line_style=) && model.respond_to?(:line_styles)
                styles = model.line_styles
                style = styles[line_style_name] if styles.respond_to?(:[])
                layer.line_style = style if style
            end

            layer
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Origin helper tag setup failed: #{error.message}")
            nil
        end

        def self.Na__Exporter__EnsureOriginHelperMaterial(model)
            if defined?(Na__EdgeColourManager) && Na__EdgeColourManager.respond_to?(:Na__EdgeColours__EnsureSketchUpMaterial)
                return Na__EdgeColourManager.Na__EdgeColours__EnsureSketchUpMaterial(model, NA_ORIGIN_HELPER_COLOUR_ID)
            end

            material_name = NA_ORIGIN_HELPER_COLOUR_ID
            material = model.materials[material_name] || model.materials.add(material_name)
            material.color = Sketchup::Color.new(229, 57, 53)
            material
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Origin helper material setup failed: #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | DataLib Helpers (Tags + Edge Materials)
    # -------------------------------------------------------------------------

        # @delegate: ../../../03__AppUtils/Na__ProfileTools__AppUtils__TagApplier__  (from 33__System__CreateProfileMode)
        def self.Na__Exporter__FindTagEntryByName(target_tag_name)
            Na__TagApplier.Na__TagApplier__FindTagEntryByName(target_tag_name)
        end

        def self.Na__Exporter__FindTagNodeRecursive(node, target_tag_name)
            Na__TagApplier.Na__TagApplier__FindTagNodeRecursive(node, target_tag_name)
        end

        def self.Na__Exporter__LoadEdgeMaterialLookup
            return @na_edge_material_lookup if @na_edge_material_lookup.is_a?(Hash)

            if defined?(Na__EdgeColourManager) && Na__EdgeColourManager.respond_to?(:Na__EdgeColours__GetEntryByName)
                @na_edge_material_lookup = Na__EdgeColourManager.Na__EdgeColours__FlatLookup
                return @na_edge_material_lookup if @na_edge_material_lookup.is_a?(Hash)
            end

            lookup = {}
            data = Na__DataLib__CacheData.Na__Cache__LoadData(:edge_materials)
            if data.is_a?(Hash)
                library = data['Na__DataLib__CoreIndex__EdgeMaterials']
                if library.is_a?(Hash)
                    library.each do |_series_key, series_value|
                        next unless series_value.is_a?(Hash)
                        series_value.each do |entry_key, entry_value|
                            next unless entry_value.is_a?(Hash)
                            lookup[entry_key] = entry_value
                            sketchup_name = entry_value['SketchUpName'].to_s
                            lookup[sketchup_name] = entry_value unless sketchup_name.empty?
                        end
                    end
                end
            end

            @na_edge_material_lookup = lookup
            lookup
        rescue
            @na_edge_material_lookup = {}
            @na_edge_material_lookup
        end

        def self.Na__Exporter__ResolveEdgeColourId(material_name)
            return nil if material_name.to_s.strip.empty?
            return material_name if material_name.start_with?('MTE')

            edge_entry = self.Na__Exporter__LoadEdgeMaterialLookup[material_name]
            return nil unless edge_entry.is_a?(Hash)
            edge_entry['SketchUpName'].to_s
        end

        def self.Na__Exporter__ResolveEdgeColourHexFallback(edge, colour_id)
            if edge.material && edge.material.color
                colour = edge.material.color
                return self.Na__Exporter__RgbToHex(colour.red, colour.green, colour.blue)
            end

            if colour_id
                edge_entry = self.Na__Exporter__LoadEdgeMaterialLookup[colour_id]
                if edge_entry.is_a?(Hash)
                    return edge_entry['HexValue'].to_s if edge_entry['HexValue'].to_s.strip.length > 0
                    if edge_entry['RgbValue'].is_a?(Array) && edge_entry['RgbValue'].length == 3
                        rgb = edge_entry['RgbValue'].map(&:to_i)
                        return self.Na__Exporter__RgbToHex(rgb[0], rgb[1], rgb[2])
                    end
                end
            end

            NA_DEFAULT_EDGE_HEX
        rescue
            NA_DEFAULT_EDGE_HEX
        end

        def self.Na__Exporter__RgbToHexFromEdge(edge)
            return NA_DEFAULT_EDGE_HEX unless edge.material && edge.material.color
            colour = edge.material.color
            self.Na__Exporter__RgbToHex(colour.red, colour.green, colour.blue)
        rescue
            NA_DEFAULT_EDGE_HEX
        end

        def self.Na__Exporter__HexToRgb(hex_value)
            sanitized_hex = hex_value.to_s.strip.delete('#')
            return [102, 102, 102] unless sanitized_hex.length == 6

            [
                sanitized_hex[0..1].to_i(16),
                sanitized_hex[2..3].to_i(16),
                sanitized_hex[4..5].to_i(16)
            ]
        rescue
            [102, 102, 102]
        end

        def self.Na__Exporter__RgbToHex(red, green, blue)
            format('#%02X%02X%02X', red.to_i, green.to_i, blue.to_i)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
