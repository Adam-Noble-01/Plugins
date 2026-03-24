# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - PROFILE EXPORTER
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__ProfileExporter__.rb
# PURPOSE    : Export selected SketchUp geometry as rich JSON profile files
# CREATED    : 2026
#
# =============================================================================

require 'json'
require 'time'

module Na__ProfileTools__ProfilePathTracer
    module Na__ProfileExporter

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_MM_PER_INCH     = 25.4
        NA_TOLERANCE_MM    = 0.0001
        NA_DATA_FILES_DIR  = File.join(File.dirname(__FILE__), '01__ProfileDataFiles').freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Selection Validation
    # -------------------------------------------------------------------------

        def self.Na__Exporter__ValidateSelection
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

            {
                'isValid' => true,
                'reason' => nil,
                'faceCount' => faces.length,
                'edgeCount' => edges.length,
                'vertexCount' => self.Na__Exporter__CountUniqueVertices(faces, edges),
                'previewPoints' => self.Na__Exporter__ExtractPreviewPoints(faces, edges)
            }
        end

        def self.Na__Exporter__ExtractPreviewPoints(faces, edges)
            if faces.any?
                face = faces.first
                face.outer_loop.vertices.map do |vertex|
                    pos = vertex.position
                    [(pos.x.to_f * NA_MM_PER_INCH).round(6), (pos.y.to_f * NA_MM_PER_INCH).round(6)]
                end
            else
                edges.flat_map { |e| [e.start, e.end] }
                     .uniq { |v| v.persistent_id }
                     .map do |vertex|
                    pos = vertex.position
                    [(pos.x.to_f * NA_MM_PER_INCH).round(6), (pos.y.to_f * NA_MM_PER_INCH).round(6)]
                end
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Entity Collection From Selection
    # -------------------------------------------------------------------------

        def self.Na__Exporter__CollectEntitiesFromSelection(entities, faces, edges)
            seen_faces = {}
            seen_edges = {}

            Array(entities).each do |entity|
                case entity
                when Sketchup::Face
                    unless seen_faces[entity.persistent_id]
                        seen_faces[entity.persistent_id] = true
                        faces << entity
                        entity.edges.each do |edge|
                            unless seen_edges[edge.persistent_id]
                                seen_edges[edge.persistent_id] = true
                                edges << edge
                            end
                        end
                    end
                when Sketchup::Edge
                    unless seen_edges[entity.persistent_id]
                        seen_edges[entity.persistent_id] = true
                        edges << entity
                    end
                when Sketchup::Group
                    self.Na__Exporter__CollectEntitiesFromSelection(entity.entities.to_a, faces, edges)
                when Sketchup::ComponentInstance
                    self.Na__Exporter__CollectEntitiesFromSelection(entity.definition.entities.to_a, faces, edges)
                end
            end
        end

        def self.Na__Exporter__CountUniqueVertices(faces, edges)
            vertex_ids = {}
            faces.each { |f| f.vertices.each { |v| vertex_ids[v.persistent_id] = true } }
            edges.each { |e| [e.start, e.end].each { |v| vertex_ids[v.persistent_id] = true } }
            vertex_ids.length
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Geometry Collection (Selection -> Hash)
    # -------------------------------------------------------------------------

        def self.Na__Exporter__CollectGeometry
            model = Sketchup.active_model
            return nil unless model

            selection = model.selection.to_a
            return nil if selection.empty?

            faces = []
            edges = []
            self.Na__Exporter__CollectEntitiesFromSelection(selection, faces, edges)

            vtx_index = {}
            vertices  = []
            edge_list = []
            face_list = []

            faces.each do |face|
                self.Na__Exporter__IndexFaceVertices(face, vtx_index, vertices)
            end
            edges.each do |edge|
                self.Na__Exporter__IndexEdgeVertices(edge, vtx_index, vertices)
            end

            edges.each do |edge|
                edge_list << self.Na__Exporter__BuildEdgeRecord(edge, vtx_index)
            end

            faces.each do |face|
                face_list << self.Na__Exporter__BuildFaceRecord(face, vtx_index)
            end

            {
                'vertices' => { 'count' => vertices.length, 'items' => vertices },
                'edges'    => { 'count' => edge_list.length, 'items' => edge_list },
                'faces'    => { 'count' => face_list.length, 'items' => face_list }
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Vertex Indexing
    # -------------------------------------------------------------------------

        def self.Na__Exporter__PointToMm(point)
            [
                (point.x.to_f * NA_MM_PER_INCH).round(6),
                (point.y.to_f * NA_MM_PER_INCH).round(6),
                (point.z.to_f * NA_MM_PER_INCH).round(6)
            ]
        end

        def self.Na__Exporter__QuantKey(mm)
            [
                (mm[0] / NA_TOLERANCE_MM).round,
                (mm[1] / NA_TOLERANCE_MM).round,
                (mm[2] / NA_TOLERANCE_MM).round
            ].join('|')
        end

        def self.Na__Exporter__IndexPoint(point, vtx_index, vertices)
            mm  = self.Na__Exporter__PointToMm(point)
            key = self.Na__Exporter__QuantKey(mm)

            return vtx_index[key] if vtx_index.key?(key)

            idx = vertices.length
            vertices << {
                'VertexId' => nil,
                'PosX'     => mm[0],
                'PosY'     => mm[1],
                'PosZ'     => mm[2],
                'W'        => 0.0
            }
            vtx_index[key] = idx
            idx
        end

        def self.Na__Exporter__IndexFaceVertices(face, vtx_index, vertices)
            face.vertices.each do |vertex|
                self.Na__Exporter__IndexPoint(vertex.position, vtx_index, vertices)
            end
        end

        def self.Na__Exporter__IndexEdgeVertices(edge, vtx_index, vertices)
            self.Na__Exporter__IndexPoint(edge.start.position, vtx_index, vertices)
            self.Na__Exporter__IndexPoint(edge.end.position, vtx_index, vertices)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Edge Record Builder
    # -------------------------------------------------------------------------

        def self.Na__Exporter__BuildEdgeRecord(edge, vtx_index)
            s_mm = self.Na__Exporter__PointToMm(edge.start.position)
            e_mm = self.Na__Exporter__PointToMm(edge.end.position)

            v1 = vtx_index[self.Na__Exporter__QuantKey(s_mm)]
            v2 = vtx_index[self.Na__Exporter__QuantKey(e_mm)]

            vec = edge.end.position - edge.start.position
            len_mm = (vec.length * NA_MM_PER_INCH).round(6)

            dir = if vec.length > 0.0
                vn = vec.clone
                vn.normalize!
                [vn.x.to_f.round(6), vn.y.to_f.round(6), vn.z.to_f.round(6)]
            else
                [0.0, 0.0, 0.0]
            end

            {
                'v1'        => v1,
                'v2'        => v2,
                'direction' => dir,
                'length_mm' => len_mm,
                'soft'      => edge.soft?,
                'smooth'    => edge.smooth?,
                'hidden'    => edge.hidden?
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Face Record Builder
    # -------------------------------------------------------------------------

        def self.Na__Exporter__BuildFaceRecord(face, vtx_index)
            outer_loop  = face.outer_loop
            inner_loops = face.loops.reject { |lp| lp == outer_loop }

            outer_indices = self.Na__Exporter__LoopVertexIndices(outer_loop, vtx_index)
            inner_indices = inner_loops.map { |lp| self.Na__Exporter__LoopVertexIndices(lp, vtx_index) }

            n = face.normal
            normal = [n.x.to_f.round(6), n.y.to_f.round(6), n.z.to_f.round(6)]
            area_mm2 = (face.area * NA_MM_PER_INCH * NA_MM_PER_INCH).round(6)

            {
                'outer'    => outer_indices,
                'inners'   => inner_indices,
                'normal'   => normal,
                'area_mm2' => area_mm2
            }
        end

        def self.Na__Exporter__LoopVertexIndices(loop, vtx_index)
            loop.vertices.map do |vertex|
                mm  = self.Na__Exporter__PointToMm(vertex.position)
                key = self.Na__Exporter__QuantKey(mm)
                vtx_index[key]
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | JSON Payload Builder
    # -------------------------------------------------------------------------

        def self.Na__Exporter__BuildJsonPayload(geometry_data, meta_fields)
            timestamp = Time.now.getlocal.strftime('%d-%b-%Y__%H:%M')

            meta = {
                'Meta_ProfileName' => meta_fields['Meta_ProfileName'].to_s,
                'Meta_Description' => meta_fields['Meta_Description'].to_s,
                'Meta_Timestamp'   => timestamp,
                'Meta_GlobalUnits' => 'millimetres',
                'Meta_Keywords'    => Array(meta_fields['Meta_Keywords']),
                'Meta_ProfileId'   => meta_fields['Meta_ProfileId'].to_s
            }

            {
                'meta'     => meta,
                'vertices' => geometry_data['vertices'],
                'edges'    => geometry_data['edges'],
                'faces'    => geometry_data['faces']
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | File Save (OS Dialog + Write)
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
                indent:       '  ',
                space:        '  ',
                space_before: '  ',
                object_nl:    "\n",
                array_nl:     "\n"
            )

            File.open(path, 'w:utf-8') { |f| f.write(JSON.generate(json_data, json_state)) }

            { 'isSaved' => true, 'filePath' => path, 'reason' => nil }
        rescue => error
            { 'isSaved' => false, 'reason' => "Save failed: #{error.message}" }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Full Export Workflow (called from DialogManager)
    # -------------------------------------------------------------------------

        def self.Na__Exporter__RunExport(meta_fields)
            geometry_data = self.Na__Exporter__CollectGeometry
            return { 'isSaved' => false, 'reason' => 'No geometry collected from selection.' } unless geometry_data

            json_data = self.Na__Exporter__BuildJsonPayload(geometry_data, meta_fields)
            suggested_name = meta_fields['Meta_ProfileId'].to_s
            suggested_name = meta_fields['Meta_ProfileName'].to_s if suggested_name.strip.empty?

            self.Na__Exporter__PromptAndSave(json_data, suggested_name)
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
