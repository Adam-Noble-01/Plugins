# =============================================================================
# NA PROFILE TOOLS - DRAW PROFILE MODE - PROFILE WRITER
# =============================================================================
#
# FILE       : Na__ProfileTools__DrawProfile__ProfileWriter__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__DrawProfile__ProfileWriter
# PURPOSE    : Writes a profile drawn in the Draw Profile tab straight into the
#              profile library, as a new data file or over an existing one.
#              No SketchUp geometry, no face to select, no origin to click.
#
# PAYLOAD (from the dialog, millimetres in the profile's own Y / Z axes)
#   'loop'        => [[y, z], ...]  the closed outer loop with every arc already
#                                   divided into its segments, no closing repeat
#   'curves'      => [{ 'startIndex' => i, 'segments' => n, 'radius' => r }]
#                    one per arc: a run of n segments that starts at loop[i]
#                    and may wrap past the end of the loop. A run of the whole
#                    loop (n == the point count) is a circle.
#   'annotations' => { 'dimensions' => [{ 'a' => [y, z], 'b' => [y, z],
#                                         'offset' => mm, 'orient' => '...' }] }
#                    editor-only audit dimensions, kept with the profile
#   'edgePaint'   => [id or nil, ...]  one per outline edge (loop[i] to loop[i + 1])
#   'vertexPaint' => [id or nil, ...]  one per outline vertex
#   'paintHex'    => { id => '#rrggbb' } the colour the dialog showed for each id
#                    Edge Paint (v1.6.15): ids are edge colours from the SSOT
#                    (Na__DataLib__CoreIndex__EdgeMaterials), or 'Default' for
#                    SketchUp's own edge colour. An edge's colour is written to
#                    its Mesh3D edge (the sweep puts it on the caps and every
#                    mitre); a vertex's to its Profile2D vertex as SweepEdge*
#                    (the line it sweeps along the path). nil: an unpainted
#                    edge takes the base profile's usual colour, an unpainted
#                    vertex follows its edges.
#
# WHAT IS WRITTEN
#   The same Profile2D / Mesh3D blocks Create Profile writes, built by the
#   exporter's own Na__Exporter__BuildGeometryBlocks, so every reader sees an
#   ordinary profile. Profile2D also carries Na__Geometry__Curves: one record
#   per arc, its vertex ids in loop order. The sweep welds each run into a
#   SketchUp curve (Na__Geometry__WeldProfileCurves); the editor reopens each
#   run as an arc rather than as loose segments.
#
#   Curve records hold ids and counts only. A centre or a bulge would go stale
#   the moment Flip Profile or a new insertion point moved the vertices; the
#   vertices themselves never do, so readers refit the circle from them.
#
# SAVE CONTRACT
#   New       a fresh file named after the profile code, never over another
#             file and never under a code the library already holds.
#   Overwrite the library path guard, a stale-file check (the file must still
#             be the profile the dialog loaded), the geometry blocks merged over
#             the old ones (hand-added keys survive), .bak written last, just
#             before the overwrite, as the Edit Profile writers do.
#   Both return the freshly re-parsed library record, so the dialog store holds
#   exactly what is on disk.
#
# =============================================================================

require 'json'
require 'time'

module Na__ProfileTools__ProfilePathTracer
    module Na__DrawProfile__ProfileWriter

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_MAX_LOOP_POINTS       = 20000
        NA_MIN_LOOP_POINTS       = 3
        NA_SAME_POINT_MM         = 0.0005
        NA_MIN_AREA_MM2          = 0.0001
        NA_MAX_DIMENSIONS        = 500
        NA_MAX_COORDINATE_MM     = 100_000.0

        NA_DEFAULT_EDGE_HEX      = '#666666'.freeze
        NA_DEFAULT_PAINT_ID      = 'Default'.freeze
        NA_PAINT_ID_PATTERN      = /\A[\w\-. ]{1,120}\z/.freeze
        NA_HEX_PATTERN           = /\A#[0-9A-Fa-f]{6}\z/.freeze
        NA_ANNOTATIONS_KEY       = 'Na__Asset__Annotations2D'.freeze
        NA_CURVES_KEY            = 'Na__Geometry__Curves'.freeze
        NA_DRAWN_ORIGIN_NOTE     = 'Local 0,0 = the datum set in the Draw Profile editor.'.freeze
        NA_DRAWN_NOTES           = 'Drawn in the Na__ProfileTools__ProfilePathTracer Draw Profile editor.'.freeze

        # Same rules the exporter and the renamer use, so a drawn profile's code
        # and file name are indistinguishable from a captured one's.
        NA_UNSAFE_CODE_CHARS     = /[^\w\-.]+/.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # params: 'geometry' (the payload above), 'meta' (Meta_ProfileName,
        # Meta_ProfileId, Meta_ProfileShortName, Meta_Description,
        # Meta_Keywords), 'baseProfileKey' (optional: the profile whose edge
        # colour the new one takes).
        def self.Na__ProfileWriter__SaveNew(params)
            params = {} unless params.is_a?(Hash)
            meta   = params['meta'].is_a?(Hash) ? params['meta'] : {}

            profile_name = meta['Meta_ProfileName'].to_s.strip
            return self.Na__ProfileWriter__Failure('Give the profile a name before saving it.') if profile_name.empty?

            profile_code = self.Na__ProfileWriter__CleanCode(meta['Meta_ProfileId'].to_s.strip.empty? ? profile_name : meta['Meta_ProfileId'])
            return self.Na__ProfileWriter__Failure('The profile code is empty once unusable characters are taken out.') if profile_code.empty?

            if Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(profile_code)
                return self.Na__ProfileWriter__Failure(
                    "The library already holds a profile coded \"#{profile_code}\". Choose another code, or save over that profile instead."
                )
            end

            file_name = Na__EditProfile__FileRenamer.Na__FileRenamer__SanitiseFileName(profile_code)
            return self.Na__ProfileWriter__Failure('No usable file name could be made from the profile code.') unless file_name

            library_dir = Na__EditProfile__LibraryPaths::NA_PROFILE_DATA_DIR
            Dir.mkdir(library_dir) unless File.directory?(library_dir)
            target_path = File.join(library_dir, file_name).tr('\\', '/')
            if File.exist?(target_path)
                return self.Na__ProfileWriter__Failure(
                    "A file named \"#{file_name}\" is already in the profile library. Choose another code."
                )
            end

            style_source = self.Na__ProfileWriter__BaseAssetData(params['baseProfileKey'])
            geometry     = self.Na__ProfileWriter__BuildGeometryData(params['geometry'], style_source)
            return self.Na__ProfileWriter__Failure(geometry[:reason]) unless geometry[:isValid]

            meta_fields = {
                'Meta_ProfileName'      => profile_name,
                'Meta_ProfileId'        => profile_code,
                'Meta_ProfileShortName' => meta['Meta_ProfileShortName'].to_s.strip,
                'Meta_Description'      => meta['Meta_Description'].to_s,
                'Meta_Keywords'         => Array(meta['Meta_Keywords']).map(&:to_s).map(&:strip).reject(&:empty?)
            }

            # @delegate: ../33__System__CreateProfileMode/Na__ProfileTools__CreateNewProfile__Exporter__
            data = Na__ProfileExporter.Na__Exporter__BuildJsonPayload(geometry[:data], meta_fields)
            data['meta']['fileName'] = file_name
            data['meta']['description'] = 'Profile drawn in Na__ProfileTools__ProfilePathTracer.'
            data['Na__Asset__Metadata']['Na__Asset__Notes'] = NA_DRAWN_NOTES
            self.Na__ProfileWriter__StampDrawnBlocks(data, params['geometry'])

            # @delegate: ../32__System__EditProfileMode/Na__ProfileTools__EditProfile__MetaWriter__
            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteFile(target_path, data)
            self.Na__ProfileWriter__ResultFor(target_path, profile_code, geometry, 'saved as a new library profile')
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__ProfileWriter__SaveNew failed.', error)
            self.Na__ProfileWriter__Failure("Save failed: #{error.message}")
        end

        # params: 'profileKey', 'sourceFile' (the library file the dialog
        # loaded), 'geometry'.
        def self.Na__ProfileWriter__SaveOverwrite(params)
            params      = {} unless params.is_a?(Hash)
            profile_key = params['profileKey'].to_s.strip
            return self.Na__ProfileWriter__Failure('No library profile is loaded to save over.') if profile_key.empty?

            path_check = Na__EditProfile__LibraryPaths.Na__LibraryPaths__ValidateProfileFile(params['sourceFile'])
            return self.Na__ProfileWriter__Failure(path_check['reason'], profile_key) unless path_check['isValid']
            expanded_path = path_check['expandedPath']

            record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(expanded_path)
            unless record && record['profileKey'].to_s == profile_key
                return self.Na__ProfileWriter__Failure(
                    "That file no longer holds profile \"#{profile_key}\" — nothing was written. Reload the profile and try again.",
                    profile_key
                )
            end

            raw_content = File.read(expanded_path, encoding: 'utf-8')
            data        = JSON.parse(raw_content)

            geometry = self.Na__ProfileWriter__BuildGeometryData(params['geometry'], data)
            return self.Na__ProfileWriter__Failure(geometry[:reason], profile_key) unless geometry[:isValid]

            # Shallow-merged, as Replace Geometry does: hand-added keys inside
            # the two blocks survive, everything else in the file is untouched.
            fresh_blocks = Na__ProfileExporter.Na__Exporter__BuildGeometryBlocks(geometry[:data])
            fresh_blocks.each do |block_key, fresh_block|
                existing = data[block_key]
                data[block_key] = existing.is_a?(Hash) ? existing.merge(fresh_block) : fresh_block
            end
            self.Na__ProfileWriter__StampDrawnBlocks(data, params['geometry'])
            (data['meta'] ||= {})['lastUpdated'] = Time.now.strftime('%d-%b-%Y')

            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteBackup(expanded_path, raw_content)
            Na__EditProfile__MetaWriter.Na__MetaWriter__WriteFile(expanded_path, data)
            self.Na__ProfileWriter__ResultFor(expanded_path, profile_key, geometry, 'saved over the library profile (backup written as .bak)')
        rescue JSON::ParserError => error
            self.Na__ProfileWriter__Failure("The library file is not valid JSON: #{error.message}", params['profileKey'].to_s)
        rescue => error
            Na__DebugTools.Na__Debug__Error('Na__ProfileWriter__SaveOverwrite failed.', error)
            self.Na__ProfileWriter__Failure("Save failed: #{error.message}", params['profileKey'].to_s)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Local Profiles (kept on one trace, not in the library)
    # -------------------------------------------------------------------------

        # The asset data a LOCAL profile carries on its trace: the same blocks a
        # library file holds (the sweep cannot tell them apart), with no file
        # and no library code. Returns { isValid, data, counts } or the refusal.
        def self.Na__ProfileWriter__BuildLocalAssetData(geometry_payload, style_source, display_name)
            geometry = self.Na__ProfileWriter__BuildGeometryData(geometry_payload, style_source)
            return geometry unless geometry[:isValid]

            name = display_name.to_s.strip
            name = 'Local profile' if name.empty?
            data = {
                'meta' => {
                    'description'      => 'Local profile drawn in the Draw Profile editor and kept on one Profile Trace.',
                    'version'          => '1.0.0',
                    'lastUpdated'      => Time.now.strftime('%d-%b-%Y'),
                    'Meta_ProfileName' => name
                },
                'Na__Asset__Metadata' => {
                    'Na__Asset__Name'  => name,
                    'Na__Asset__Code'  => 'LOCAL',
                    'Na__Asset__Type'  => 'Profile2D',
                    'Na__Asset__Notes' => NA_DRAWN_NOTES
                }
            }.merge(Na__ProfileExporter.Na__Exporter__BuildGeometryBlocks(geometry[:data]))
            self.Na__ProfileWriter__StampDrawnBlocks(data, geometry_payload)
            { isValid: true, data: data, counts: geometry[:counts] }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Geometry Data (dialog payload -> exporter-shaped blocks)
    # -------------------------------------------------------------------------

        # Returns { isValid: true, data: geometry_data, counts: {...} } where
        # geometry_data is the hash Na__Exporter__BuildGeometryBlocks reads, or
        # { isValid: false, reason: '...' }. Nothing is guessed at: a payload
        # that is not exactly one clean closed loop is refused with the fix.
        def self.Na__ProfileWriter__BuildGeometryData(payload, style_source = nil)
            payload = {} unless payload.is_a?(Hash)

            loop_check = self.Na__ProfileWriter__NormaliseLoop(payload['loop'])
            return loop_check unless loop_check[:isValid]
            points = loop_check[:points]

            curves = self.Na__ProfileWriter__NormaliseCurves(payload['curves'], points.length)
            style  = self.Na__ProfileWriter__DominantEdgeStyle(style_source)
            paints = self.Na__ProfileWriter__NormalisePaints(payload, points.length)

            vertex_ids = (1..points.length).map { |index| format('V%03d', index) }
            profile_vertices = points.each_with_index.map do |(y_mm, z_mm), index|
                vertex = { 'VertexId' => vertex_ids[index], 'PosY_mm' => y_mm, 'PosZ_mm' => z_mm }
                sweep_paint = paints[:vertices][index]
                vertex.merge!(self.Na__ProfileWriter__SweepFields(sweep_paint, paints[:hex][sweep_paint])) if sweep_paint
                vertex
            end

            profile_edges = []
            mesh_edges    = []
            points.length.times do |index|
                edge_id  = format('E%03d', index + 1)
                start_id = vertex_ids[index]
                end_id   = vertex_ids[(index + 1) % points.length]
                edge_paint = paints[:edges][index]
                edge_style = edge_paint ? self.Na__ProfileWriter__PaintStyle(edge_paint, paints[:hex][edge_paint]) : style
                profile_edges << { 'EdgeId' => edge_id, 'StartVertex' => start_id, 'EndVertex' => end_id }
                mesh_edges << {
                    'EdgeId'           => edge_id,
                    'StartVertex'      => start_id,
                    'EndVertex'        => end_id,
                    'IsSoft'           => false,
                    'IsSmooth'         => false,
                    'IsHidden'         => false,
                    'CastsShadows'     => true,
                    'EdgeMaterialName' => edge_style['EdgeMaterialName'],
                    'EdgeColourId'     => edge_style['EdgeColourId'],
                    'EdgeColourHex'    => edge_style['EdgeColourHex']
                }
            end

            profile_faces = [{ 'FaceId' => 'F001', 'OuterLoopVertices' => vertex_ids.dup }]
            curve_records = curves.each_with_index.map do |curve, index|
                record = {
                    'CurveId'   => format('C%03d', index + 1),
                    'CurveType' => curve['isClosed'] ? 'Circle' : 'Arc',
                    'Segments'  => curve['segments'],
                    'VertexIds' => curve['indices'].map { |vertex_index| vertex_ids[vertex_index] }
                }
                record['Radius_mm'] = curve['radius'].round(6) if curve['radius'] > 0
                record['IsClosed'] = true if curve['isClosed']
                record
            end

            mesh_vertices = Na__ProfileExporter.Na__Exporter__BuildMeshVertices(profile_vertices)
            mesh_faces    = Na__ProfileExporter.Na__Exporter__BuildMeshFaces(profile_faces)

            {
                isValid: true,
                counts: {
                    vertices: points.length, curves: curve_records.length,
                    paintedEdges: paints[:edges].compact.length, paintedVertices: paints[:vertices].compact.length
                },
                data: {
                    'profileVertices' => profile_vertices,
                    'profileEdges'    => profile_edges,
                    'profileFaces'    => profile_faces,
                    'profileCurves'   => curve_records,
                    'meshVertices'    => mesh_vertices,
                    'meshEdges'       => mesh_edges,
                    'meshFaces'       => mesh_faces,
                    'meshBoundingBox' => Na__ProfileExporter.Na__Exporter__BuildMeshBoundingBox(mesh_vertices)
                }
            }
        end

        def self.Na__ProfileWriter__NormaliseLoop(raw_loop)
            unless raw_loop.is_a?(Array)
                return { isValid: false, reason: 'The drawing sent no outline. Close the profile into one loop, then save.' }
            end
            if raw_loop.length < NA_MIN_LOOP_POINTS
                return { isValid: false, reason: 'The outline needs at least three points.' }
            end
            if raw_loop.length > NA_MAX_LOOP_POINTS
                return { isValid: false, reason: "The outline has #{raw_loop.length} points, over the #{NA_MAX_LOOP_POINTS} limit. Use fewer arc segments." }
            end

            points = []
            raw_loop.each_with_index do |pair, index|
                y_mm = self.Na__ProfileWriter__FiniteFloat(pair.is_a?(Array) ? pair[0] : nil)
                z_mm = self.Na__ProfileWriter__FiniteFloat(pair.is_a?(Array) ? pair[1] : nil)
                unless y_mm && z_mm && y_mm.abs <= NA_MAX_COORDINATE_MM && z_mm.abs <= NA_MAX_COORDINATE_MM
                    return { isValid: false, reason: "Point #{index + 1} of the outline is not a usable coordinate." }
                end
                points << [y_mm.round(6), z_mm.round(6)]
            end

            # Refused, not quietly merged: dropping a point would shift every
            # curve index after it, and the editor never sends one anyway.
            points.each_with_index do |point, index|
                following = points[(index + 1) % points.length]
                next unless self.Na__ProfileWriter__SamePoint?(point, following)
                return { isValid: false, reason: "Points #{index + 1} and #{((index + 1) % points.length) + 1} of the outline sit on top of each other. Run Check Profile in the Draw tab." }
            end

            if self.Na__ProfileWriter__SignedArea(points).abs < NA_MIN_AREA_MM2
                return { isValid: false, reason: 'The outline encloses no area.' }
            end

            { isValid: true, points: points }
        end

        # Each curve becomes { 'indices', 'segments', 'radius', 'isClosed' }.
        # Anything that does not describe a run inside the loop is dropped (the
        # outline itself is still right, it just reopens as segments), and so
        # is a run that would share a segment with one already taken.
        def self.Na__ProfileWriter__NormaliseCurves(raw_curves, point_count)
            taken_segments = {}
            Array(raw_curves).each_with_object([]) do |curve, list|
                next unless curve.is_a?(Hash)
                start_index = self.Na__ProfileWriter__WholeNumber(curve['startIndex'])
                segments    = self.Na__ProfileWriter__WholeNumber(curve['segments'])
                next unless start_index && segments
                next if start_index < 0 || start_index >= point_count
                next if segments < 2 || segments > point_count

                is_closed = segments == point_count
                segment_slots = (0...segments).map { |step| (start_index + step) % point_count }
                next if segment_slots.any? { |slot| taken_segments[slot] }
                segment_slots.each { |slot| taken_segments[slot] = true }

                indices = (0..segments).map { |step| (start_index + step) % point_count }
                indices.pop if is_closed
                radius = self.Na__ProfileWriter__FiniteFloat(curve['radius']) || 0.0
                list << { 'indices' => indices, 'segments' => segments, 'radius' => radius.abs, 'isClosed' => is_closed }
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Drawn-Profile Blocks
    # -------------------------------------------------------------------------

        # The origin note is rewritten (there was no click), and the editor's
        # audit dimensions ride along in their own top-level block, which no
        # reader of the profile geometry looks at.
        def self.Na__ProfileWriter__StampDrawnBlocks(data, geometry_payload)
            profile_block = data['Na__Asset__Profile2D']
            profile_block['Na__Geometry__OriginNote'] = NA_DRAWN_ORIGIN_NOTE if profile_block.is_a?(Hash)

            dimensions = self.Na__ProfileWriter__NormaliseDimensions(geometry_payload)
            if dimensions.empty?
                data.delete(NA_ANNOTATIONS_KEY)
            else
                data[NA_ANNOTATIONS_KEY] = {
                    'Na__Annotation__Note'       => 'Audit dimensions from the Draw Profile editor. Not profile geometry.',
                    'Na__Annotation__Dimensions' => dimensions
                }
            end
        end

        def self.Na__ProfileWriter__NormaliseDimensions(geometry_payload)
            annotations = geometry_payload.is_a?(Hash) ? geometry_payload['annotations'] : nil
            raw_list    = annotations.is_a?(Hash) ? Array(annotations['dimensions']) : []
            orients     = %w[aligned horizontal vertical]

            raw_list.first(NA_MAX_DIMENSIONS).each_with_index.each_with_object([]) do |(dimension, index), list|
                next unless dimension.is_a?(Hash)
                start_point = dimension['a']
                end_point   = dimension['b']
                next unless start_point.is_a?(Array) && end_point.is_a?(Array)
                coords = [start_point[0], start_point[1], end_point[0], end_point[1], dimension['offset']].map do |value|
                    self.Na__ProfileWriter__FiniteFloat(value)
                end
                next if coords.any?(&:nil?)
                orient = orients.include?(dimension['orient'].to_s) ? dimension['orient'].to_s : 'aligned'
                list << {
                    'DimensionId' => format('D%03d', index + 1),
                    'Orientation' => orient,
                    'StartY_mm'   => coords[0].round(6),
                    'StartZ_mm'   => coords[1].round(6),
                    'EndY_mm'     => coords[2].round(6),
                    'EndZ_mm'     => coords[3].round(6),
                    'Offset_mm'   => coords[4].round(6)
                }
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Edge Paint (v1.6.15)
    # -------------------------------------------------------------------------

        # { edges: [id|nil] x count, vertices: [id|nil] x count, hex: {id => hex} }.
        # A list of the wrong length is dropped whole, never shifted onto the
        # wrong edges; an id that is not a plain name is dropped on its own.
        def self.Na__ProfileWriter__NormalisePaints(payload, count)
            read = lambda do |raw|
                list = raw.is_a?(Array) && raw.length == count ? raw : []
                Array.new(count) { |index| self.Na__ProfileWriter__CleanPaintId(list[index]) }
            end
            hex = {}
            raw_hex = payload['paintHex']
            if raw_hex.is_a?(Hash)
                raw_hex.each do |id, value|
                    clean = self.Na__ProfileWriter__CleanPaintId(id)
                    hex[clean] = value.to_s.upcase if clean && value.to_s =~ NA_HEX_PATTERN
                end
            end
            { edges: read.call(payload['edgePaint']), vertices: read.call(payload['vertexPaint']), hex: hex }
        end

        def self.Na__ProfileWriter__CleanPaintId(value)
            return nil unless value.is_a?(String)
            text = value.strip
            text =~ NA_PAINT_ID_PATTERN ? text : nil
        end

        # An id -> the three fields every reader of a profile edge knows. The
        # registry gives the canonical key and its exact colour; 'Default' is
        # SketchUp's own edge colour (no material: the sweep leaves the edge
        # unpainted); an id the registry does not hold (offline, or a custom
        # material) keeps the colour the dialog showed, so nothing is silently
        # recoloured.
        def self.Na__ProfileWriter__PaintStyle(paint_id, fallback_hex = nil)
            if paint_id == NA_DEFAULT_PAINT_ID
                return { 'EdgeMaterialName' => '', 'EdgeColourId' => NA_DEFAULT_PAINT_ID, 'EdgeColourHex' => '' }
            end
            entry = defined?(Na__EdgeColourManager) ? Na__EdgeColourManager.Na__EdgeColours__GetEntryByName(paint_id) : nil
            if entry
                key = entry['MteKey'].to_s.empty? ? paint_id : entry['MteKey'].to_s
                hex = entry['HexValue'].to_s =~ NA_HEX_PATTERN ? entry['HexValue'].to_s.upcase : (fallback_hex || NA_DEFAULT_EDGE_HEX)
                return { 'EdgeMaterialName' => key, 'EdgeColourId' => key, 'EdgeColourHex' => hex }
            end
            { 'EdgeMaterialName' => paint_id, 'EdgeColourId' => paint_id, 'EdgeColourHex' => fallback_hex || NA_DEFAULT_EDGE_HEX }
        end

        # A vertex's colour, as the line it sweeps along the path carries it.
        def self.Na__ProfileWriter__SweepFields(paint_id, fallback_hex = nil)
            style = self.Na__ProfileWriter__PaintStyle(paint_id, fallback_hex)
            {
                'SweepEdgeMaterialName' => style['EdgeMaterialName'],
                'SweepEdgeColourId'     => style['EdgeColourId'],
                'SweepEdgeColourHex'    => style['EdgeColourHex']
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Edge Style
    # -------------------------------------------------------------------------

        # An unpainted edge takes the colour most of the base profile's edges
        # had, so new edges drawn into a profile match it. A brand-new drawing
        # takes the exporter's default for an unpainted edge.
        def self.Na__ProfileWriter__DominantEdgeStyle(asset_data)
            default_style = { 'EdgeMaterialName' => '', 'EdgeColourId' => '', 'EdgeColourHex' => NA_DEFAULT_EDGE_HEX }
            return default_style unless asset_data.is_a?(Hash)

            mesh_block = asset_data['Na__Asset__Mesh3D']
            edges = mesh_block.is_a?(Hash) ? Array(mesh_block['Na__Geometry__Edges']).select { |edge| edge.is_a?(Hash) } : []
            return default_style if edges.empty?

            tally = Hash.new(0)
            edges.each do |edge|
                tally[[edge['EdgeMaterialName'].to_s, edge['EdgeColourId'].to_s, edge['EdgeColourHex'].to_s]] += 1
            end
            material_name, colour_id, colour_hex = tally.max_by { |_, count| count }.first
            {
                'EdgeMaterialName' => material_name,
                'EdgeColourId'     => colour_id,
                'EdgeColourHex'    => colour_hex.strip.empty? ? NA_DEFAULT_EDGE_HEX : colour_hex
            }
        rescue
            { 'EdgeMaterialName' => '', 'EdgeColourId' => '', 'EdgeColourHex' => NA_DEFAULT_EDGE_HEX }
        end

        def self.Na__ProfileWriter__BaseAssetData(base_profile_key)
            key = base_profile_key.to_s.strip
            return nil if key.empty?
            record = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(key)
            record ? record.dig('profileData', 'assetData') : nil
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Result Helpers
    # -------------------------------------------------------------------------

        def self.Na__ProfileWriter__ResultFor(file_path, profile_key, geometry, verb_phrase)
            fresh_record = Na__ProfileLibrary.Na__ProfileLibrary__ParseDataFile(file_path)
            unless fresh_record
                return self.Na__ProfileWriter__Failure(
                    'The file was written but did not read back as a profile. Restore the .bak beside it if there is one.',
                    profile_key
                )
            end

            display_name = fresh_record['displayName'].to_s.strip
            display_name = profile_key if display_name.empty?
            counts = geometry[:counts]
            curve_note = counts[:curves] > 0 ? ", #{counts[:curves]} curve(s)" : ''
            {
                'isSaved'       => true,
                'profileKey'    => fresh_record['profileKey'].to_s,
                'profileRecord' => fresh_record,
                'filePath'      => file_path,
                'reason'        => nil,
                'statusMessage' => "\"#{display_name}\" #{verb_phrase} — #{counts[:vertices]} vertices#{curve_note}."
            }
        end

        def self.Na__ProfileWriter__Failure(reason, profile_key = '')
            {
                'isSaved'       => false,
                'profileKey'    => profile_key.to_s,
                'reason'        => reason.to_s,
                'statusMessage' => "Not saved: #{reason}"
            }
        end

        def self.Na__ProfileWriter__CleanCode(raw_code)
            raw_code.to_s.strip.gsub(NA_UNSAFE_CODE_CHARS, '__').sub(/\A_+/, '').sub(/[_.]+\z/, '')
        end

        def self.Na__ProfileWriter__FiniteFloat(value)
            return nil if value.nil? || value == true || value == false
            number = Float(value)
            number.finite? ? number : nil
        rescue ArgumentError, TypeError
            nil
        end

        def self.Na__ProfileWriter__WholeNumber(value)
            number = self.Na__ProfileWriter__FiniteFloat(value)
            return nil unless number && (number - number.round).abs < 1e-9
            number.round
        end

        def self.Na__ProfileWriter__SamePoint?(point_a, point_b)
            (point_a[0] - point_b[0]).abs <= NA_SAME_POINT_MM && (point_a[1] - point_b[1]).abs <= NA_SAME_POINT_MM
        end

        def self.Na__ProfileWriter__SignedArea(points)
            area = 0.0
            points.each_with_index do |point, index|
                following = points[(index + 1) % points.length]
                area += (point[0] * following[1]) - (following[0] * point[1])
            end
            area / 2.0
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
