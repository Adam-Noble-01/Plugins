# =============================================================================
# NA PROFILE TOOLS - MCP OPERATIONS - PROFILES (LIBRARY READS, SOURCES, SHAPES)
# =============================================================================
#
# FILE       : Na__ProfileTracer__McpOperations__Profiles__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__McpOperations
# AUTHOR     : Noble Architecture
# PURPOSE    : The profile half of the seam: reading the library (profiles,
#              profile), resolving where a profile comes from for a build or a
#              save, and reshaping one (profile_edit)
# CREATED    : 11-Nov-2026 (v1.6.17)
#
# WHERE A PROFILE COMES FROM (exactly one per call):
#   profile_key        a library profile, as the Gallery holds it
#   profile_from       a trace's own profile: its local one when it has one
#                      (Adam's Draw Profile edits), else its library profile
#   profile_outline    { points: [[y, z], ...], arcs: [{ start, segments,
#                      radius }], edge_colour, vertex_colours, edge_colours }:
#                      a new outline in mm, built by the Draw Profile writer
#   profile_json       a whole unified profile (the library file format)
#   profile_face_id    a face in the model: its outer loop, as Draw Profile's
#                      From Model reads it (lower-left corner at the datum)
#
# RESHAPING (profile_edit), applied in this order, every step pure data:
#   scale    a number, or [across, up]: every coordinate multiplied
#   size     { width, height } in mm: scales the axis named to that size
#            (keep_aspect: true scales both by the one given)
#   stretch  [{ axis: 'y'|'z', at: mm, by: mm, side: 'above'|'below' }]: every
#            point beyond the cut moves by 'by', the rest stays put. This is
#            how a capping is made deeper for a thicker wall or taller for a
#            drawing without distorting its mouldings (Adam's 140 high
#            Georgian capping, 11-Nov-2026: +30 up, +75 across the wall)
#   flip     true: mirrored left to right about the datum (Edit Profile's own
#            Flip Profile, Na__GeometryWriter__FlipHorizontal)
#   datum    [y, z]: that point of the profile becomes 0,0 (Edit Profile's
#            own Re-datum, Na__DatumWriter__ReDatum)
# Arcs that a scale or stretch leaves circular keep their radius; one it
# distorts loses it (a reader refits a circle from the vertices, and a
# distorted run stays as plain segments).
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Read - profiles (the library)
# -----------------------------------------------------------------------------

        def self.na_read_profiles(params)
            model   = params['model_object'] || Sketchup.active_model
            records = Na__ProfileLibrary.Na__ProfileLibrary__EnabledProfiles
            usage   = model ? self.na_key_usage(model) : {}
            words   = self.na_text(params, 'query', '').downcase.split(/[\s_\-]+/).reject(&:empty?)

            rows = records.map { |record| self.na_profile_row(record, usage) }
            unless words.empty?
                rows = rows.select do |row|
                    haystack = [row['key'], row['name'], row['short_name'], row['description'], Array(row['keywords']).join(' '), row['file']]
                               .join(' ').downcase.gsub(/[_\-]+/, ' ')
                    words.all? { |word| haystack.include?(word) }
                end
            end

            near = params['near']
            if near.is_a?(Hash) && (near.key?('width') || near.key?('height'))
                want_w = near['width'].nil? ? nil : near['width'].to_f
                want_h = near['height'].nil? ? nil : near['height'].to_f
                rows.each do |row|
                    size = row['size_mm']
                    next row['distance_mm'] = nil unless size
                    dw = want_w ? (size[0] - want_w) : 0.0
                    dh = want_h ? (size[1] - want_h) : 0.0
                    row['distance_mm'] = Math.sqrt(dw * dw + dh * dh).round(1)
                end
                rows = rows.sort_by { |row| row['distance_mm'] || Float::INFINITY }
            else
                rows = rows.sort_by { |row| row['key'].to_s.downcase }
            end

            total  = rows.length
            offset = self.na_offset(params)
            limit  = self.na_limit(params, 50, 500)
            page   = rows[offset, limit] || []
            {
                'profiles' => page,
                'total'    => total,
                'offset'   => offset,
                'next_offset' => offset + page.length < total ? offset + page.length : nil,
                'summary'  => "#{total} library profile(s)#{words.empty? ? '' : " match \"#{words.join(' ')}\""}; #{page.length} returned."
            }
        end

        # traces per ProfileKey in the model (local ones count against the key
        # they were drawn from).
        def self.na_key_usage(model)
            self.na_all_traces(model).each_with_object(Hash.new(0)) do |group, tally|
                dict = group.attribute_dictionary(Na__DataSerializer::NA_PROFILE_TRACE_DICT)
                tally[dict['ProfileKey'].to_s] += 1 if dict
            end
        end

        def self.na_profile_row(record, usage = {})
            asset = record.dig('profileData', 'assetData') || {}
            shape = self.na_shape_facts(asset)
            meta  = asset['meta'] || {}
            info  = asset['Na__Asset__Metadata'] || {}
            {
                'key'         => record['profileKey'].to_s,
                'name'        => record['displayName'].to_s,
                'short_name'  => record['shortName'].to_s,
                'category'    => record['category'].to_s,
                'description' => info['Na__Asset__Description'].to_s,
                'keywords'    => Array(meta['Meta_ProfileKeywords']).empty? ? Array(meta['Meta_Keywords']) : Array(meta['Meta_ProfileKeywords']),
                'file'        => File.basename(record['sourceFile'].to_s),
                'size_mm'     => shape['size_mm'],
                'extent_mm'   => shape['extent_mm'],
                'vertices'    => shape['vertices'],
                'faces'       => shape['faces'],
                'arcs'        => shape['arcs'],
                'edge_colour' => shape['edge_colour'],
                'traces_in_model' => usage[record['profileKey'].to_s].to_i
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Read - profile (one, in full)
# -----------------------------------------------------------------------------

        def self.na_read_profile(params)
            source = if self.na_has?(params, 'profile_key') || self.na_has?(params, 'key')
                         params['profile_key'] ||= params['key']
                         self.na_profile_source(params, required: true)
                     elsif self.na_has?(params, 'profile_from') || self.na_has?(params, 'id') || self.na_has?(params, 'trace_id')
                         params['profile_from'] ||= (params['trace_id'] || params['id'])
                         self.na_profile_source(params, required: true)
                     else
                         self.na_refuse('invalid_params', 'Say which profile: key (a library profile) or id / trace_id (a trace\'s own profile).',
                                        'profile_tracer {action: "profiles", query: "capping"} lists the library.')
                     end
            source = self.na_apply_profile_edit(source, params['profile_edit'], params['local_name']) if params['profile_edit'].is_a?(Hash)

            asset = source[:asset]
            shape = self.na_shape_facts(asset)
            max_points = [[self.na_number(params, 'max_points', 400).to_i, 3].max, 5000].min
            outline = self.na_outline(asset)
            result = {
                'key'         => source[:key],
                'name'        => source[:name],
                'source'      => source[:kind],
                'local'       => source[:local],
                'file'        => source[:file],
                'size_mm'     => shape['size_mm'],
                'extent_mm'   => shape['extent_mm'],
                'vertices'    => shape['vertices'],
                'faces'       => shape['faces'],
                'arcs'        => shape['arcs'],
                'edge_colour' => shape['edge_colour'],
                'edge_colours' => shape['edge_colours'],
                'origin_note' => asset.dig('Na__Asset__Profile2D', 'Na__Geometry__OriginNote').to_s,
                'axes'        => 'y = across the profile (the side it sits on), z = up; the datum 0,0 is the point that rides along the path'
            }
            result['edited'] = source[:edits] if source[:edits]
            if self.na_bool(params, 'include_outline', true) && outline
                points = outline[:points]
                result['outline'] = points.length <= max_points ? points.map { |y, z| [y.round(3), z.round(3)] } : nil
                result['outline_note'] = "#{points.length} points, more than max_points #{max_points}: raise max_points to see them." if points.length > max_points
                result['arc_runs'] = outline[:arcs]
            end
            result['json'] = asset if self.na_bool(params, 'include_json', false)
            result['summary'] = "#{source[:name]}: #{shape['size_mm'] ? "#{shape['size_mm'][0]} wide x #{shape['size_mm'][1]} high mm" : 'no size'}, #{shape['vertices']} vertices, #{shape['arcs']} arc run(s)#{source[:local] ? ' (a local profile)' : ''}."
            result
        end

        # Size, extent and edge colours from a unified asset, read from the
        # Profile2D vertices (the geometry the sweep uses).
        def self.na_shape_facts(asset)
            block    = asset.is_a?(Hash) ? (asset['Na__Asset__Profile2D'] || {}) : {}
            vertices = Array(block['Na__Geometry__Vertices']).select { |vertex| vertex.is_a?(Hash) }
            ys = vertices.map { |vertex| vertex['PosY_mm'].to_f }
            zs = vertices.map { |vertex| vertex['PosZ_mm'].to_f }
            mesh_edges = Array(asset.is_a?(Hash) ? asset.dig('Na__Asset__Mesh3D', 'Na__Geometry__Edges') : nil).select { |edge| edge.is_a?(Hash) }
            tally = Hash.new(0)
            mesh_edges.each { |edge| tally[(edge['EdgeColourId'].to_s.empty? ? edge['EdgeMaterialName'] : edge['EdgeColourId']).to_s] += 1 }
            {
                'size_mm'      => ys.empty? ? nil : [(ys.max - ys.min).round(3), (zs.max - zs.min).round(3)],
                'extent_mm'    => ys.empty? ? nil : { 'y' => [ys.min.round(3), ys.max.round(3)], 'z' => [zs.min.round(3), zs.max.round(3)] },
                'vertices'     => vertices.length,
                'faces'        => Array(block['Na__Geometry__Faces']).length,
                'arcs'         => Array(block['Na__Geometry__Curves']).length,
                'edge_colour'  => tally.empty? ? nil : tally.max_by { |_, count| count }.first,
                'edge_colours' => tally
            }
        end

        # The first face's outer loop as [[y, z], ...] plus its arc runs as
        # loop indices, or nil when the asset has no usable face.
        def self.na_outline(asset)
            block = asset.is_a?(Hash) ? asset['Na__Asset__Profile2D'] : nil
            return nil unless block.is_a?(Hash)
            by_id = {}
            Array(block['Na__Geometry__Vertices']).each do |vertex|
                next unless vertex.is_a?(Hash)
                by_id[vertex['VertexId'].to_s] = [vertex['PosY_mm'].to_f, vertex['PosZ_mm'].to_f]
            end
            face = Array(block['Na__Geometry__Faces']).find { |record| record.is_a?(Hash) }
            return nil unless face
            ids = Array(face['OuterLoopVertices']).map(&:to_s)
            points = ids.map { |id| by_id[id] }.compact
            return nil if points.length < 3
            index_of = {}
            ids.each_with_index { |id, index| index_of[id] ||= index }
            arcs = Array(block['Na__Geometry__Curves']).map do |curve|
                next nil unless curve.is_a?(Hash)
                indices = Array(curve['VertexIds']).map { |id| index_of[id.to_s] }.compact
                next nil if indices.length < 2
                { 'start' => indices.first, 'segments' => curve['Segments'].to_i, 'radius' => curve['Radius_mm'], 'type' => curve['CurveType'].to_s }
            end.compact
            { points: points, arcs: arcs, ids: ids }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Profile Sources (exactly one per call)
# -----------------------------------------------------------------------------

        NA_SOURCE_KEYS = %w[profile_key profile_from profile_outline profile_json profile_face_id].freeze unless defined?(NA_SOURCE_KEYS)

        # { kind:, key:, name:, asset:, record:, local:, file:, edits: }
        #   key    the library key a trace stamps (a local profile keeps the key
        #          it was drawn from)
        #   local  true when the trace must carry the asset as its own profile
        # required: false returns nil when no source key was given.
        def self.na_profile_source(params, required: false, default_key: nil)
            given = NA_SOURCE_KEYS.select { |key| self.na_has?(params, key) }
            given.delete('profile_face_id') unless params['profile_face_object']
            if given.length > 1
                self.na_refuse('invalid_params', "Give one profile source, not #{given.join(' and ')}.",
                               'profile_key (library), profile_from (a trace), profile_outline (new points), profile_json or profile_face_id.')
            end
            if given.empty?
                return nil unless required
                self.na_refuse('invalid_params', 'Say which profile to use.',
                               'Pass profile_key (find one with profile_tracer {action: "profiles", query: "capping", near: {height: 150}}), or profile_from (a trace id), profile_outline, profile_json or profile_face_id.')
            end

            base_key = default_key.to_s
            case given.first
            when 'profile_key'
                self.na_source_from_library(params['profile_key'].to_s.strip)
            when 'profile_from'
                self.na_source_from_trace(params)
            when 'profile_outline'
                self.na_source_from_outline(params['profile_outline'], params['local_name'], base_key)
            when 'profile_json'
                self.na_source_from_json(params['profile_json'], params['local_name'], base_key)
            when 'profile_face_id'
                self.na_source_from_face(params['profile_face_object'], params['local_name'], base_key)
            end
        end

        def self.na_source_from_library(key)
            self.na_refuse('invalid_params', 'profile_key is empty.', 'Pass a library key from profile_tracer {action: "profiles"}.') if key.empty?
            record = Na__ProfileLibrary.Na__ProfileLibrary__FindByKey(key)
            unless record
                close = self.na_close_keys(key)
                self.na_refuse('not_found', "There is no library profile '#{key}'.",
                               close.empty? ? 'profile_tracer {action: "profiles", query: "..."} lists the library.' : "Did you mean: #{close.join(', ')}?")
            end
            unless Na__ProfilePlacementEngine.Na__Engine__UnifiedProfileRecord?(record)
                self.na_refuse('unsupported', "Profile '#{key}' is not in the unified format the sweep needs.", 'Re-save it from the Edit Profile tab, or pick another.')
            end
            { kind: 'library', key: key, name: record['displayName'].to_s, asset: record.dig('profileData', 'assetData'),
              record: record, local: false, file: record['sourceFile'].to_s }
        end

        def self.na_close_keys(key)
            words = key.downcase.split(/[_\-\s]+/).reject { |word| word.length < 3 }
            Na__ProfileLibrary.Na__ProfileLibrary__EnabledProfiles.map { |record| record['profileKey'].to_s }
                              .select { |candidate| words.any? { |word| candidate.downcase.include?(word) } }.first(5)
        end

        def self.na_source_from_trace(params)
            group = self.na_trace_from_reference(params, params['profile_from'], 'profile_from')
            payload = Na__DataSerializer.Na__DataSerializer__ReadParentPayload(group) || {}
            key = payload['ProfileKey'].to_s
            if payload['ProfileSource'] == 'local'
                record = Na__DataSerializer.Na__DataSerializer__LocalProfileRecord(group)
                if record
                    return { kind: 'trace_local', key: key, name: payload['LocalProfileName'].to_s.empty? ? record['displayName'].to_s : payload['LocalProfileName'].to_s,
                             asset: record.dig('profileData', 'assetData'), record: record, local: true, file: '',
                             from_trace: payload['ProfileTraceId'] }
                end
            end
            source = self.na_source_from_library(key)
            source.merge(kind: 'trace_library', from_trace: payload['ProfileTraceId'])
        end

        def self.na_source_from_outline(outline, local_name, base_key)
            self.na_refuse('invalid_params', 'profile_outline must be an object with points.', 'e.g. {points: [[0,0],[300,0],[300,140],[0,140]]}') unless outline.is_a?(Hash)
            points = Array(outline['points'])
            if points.length < 3 || points.any? { |point| !point.is_a?(Array) || point.length != 2 || !point.all? { |value| value.is_a?(Numeric) } }
                self.na_refuse('invalid_params', 'profile_outline.points needs three or more [y, z] pairs in mm.',
                               'y runs across the profile, z up; 0,0 is the datum that rides along the path. No closing repeat.')
            end
            arcs = Array(outline['arcs']).map do |arc|
                next nil unless arc.is_a?(Hash)
                { 'startIndex' => arc['start'].to_i, 'segments' => arc['segments'].to_i, 'radius' => arc['radius'].to_f }
            end.compact
            payload = { 'loop' => points.map { |y, z| [y.to_f, z.to_f] }, 'curves' => arcs }
            colour = outline['edge_colour'].to_s.strip
            payload['edgePaint'] = Array.new(points.length, colour) unless colour.empty?
            payload['edgePaint'] = Array(outline['edge_colours']) if outline['edge_colours'].is_a?(Array)
            payload['vertexPaint'] = Array(outline['vertex_colours']) if outline['vertex_colours'].is_a?(Array)
            self.na_source_from_payload(payload, local_name, base_key, 'outline')
        end

        def self.na_source_from_face(face, local_name, base_key)
            self.na_refuse('invalid_params', 'profile_face_id is not a face.', 'Pass the persistent id of one face.') unless face.is_a?(Sketchup::Face)
            payload = Na__DrawProfile__TraceBridge.Na__TraceBridge__FacePayload([face])
            self.na_refuse('invalid_params', payload['statusMessage'].to_s, nil) unless payload['isResolved']
            source = self.na_source_from_payload(payload, local_name, base_key, 'face')
            source[:notes] = [payload['statusMessage'].to_s]
            source
        end

        # A Draw Profile payload -> a local asset, built by the Draw Profile
        # writer itself (one closed loop, area, arcs, edge paint, all checked).
        def self.na_source_from_payload(payload, local_name, base_key, kind)
            style_source = base_key.to_s.empty? ? nil : Na__DrawProfile__ProfileWriter.Na__ProfileWriter__BaseAssetData(base_key)
            name = local_name.to_s.strip
            name = base_key.to_s.empty? ? 'MCP drawn profile' : base_key.to_s if name.empty?
            local = Na__DrawProfile__ProfileWriter.Na__ProfileWriter__BuildLocalAssetData(payload, style_source, name)
            self.na_refuse('invalid_params', "The outline is not a usable profile: #{local[:reason]}", 'Send one closed loop of distinct points with some area, no closing repeat.') unless local[:isValid]
            { kind: kind, key: base_key.to_s.empty? ? name : base_key.to_s, name: name, asset: local[:data], record: nil,
              local: true, file: '', payload: payload }
        end

        def self.na_source_from_json(json, local_name, base_key)
            data = json.is_a?(String) ? (JSON.parse(json) rescue nil) : self.na_deep_copy(json)
            unless data.is_a?(Hash) && Na__ProfileLibrary.Na__ProfileLibrary__ValidUnifiedSchema?(data)
                self.na_refuse('invalid_params', 'profile_json is not a unified profile.',
                               'It needs meta, Na__Asset__Metadata, Na__Asset__Profile2D (Vertices, Edges, Faces) and Na__Asset__Mesh3D (Edges): the library file format.')
            end
            name = local_name.to_s.strip
            name = data.dig('Na__Asset__Metadata', 'Na__Asset__Name').to_s if name.empty?
            name = 'MCP profile' if name.empty?
            key = base_key.to_s.empty? ? (data.dig('Na__Asset__Metadata', 'Na__Asset__Code').to_s.empty? ? name : data.dig('Na__Asset__Metadata', 'Na__Asset__Code').to_s) : base_key.to_s
            { kind: 'json', key: key, name: name, asset: data, record: nil, local: true, file: '' }
        end

        # The unified record the sweep reads, for any source.
        def self.na_sweep_record(source)
            return source[:record].merge('profileKey' => source[:key]) if source[:record] && !source[:local]
            {
                'profileKey'  => source[:key],
                'displayName' => source[:name],
                'profileData' => {
                    'type'           => 'na_unified_asset',
                    'schemaContract' => 'meta + Na__Asset__Metadata + Na__Asset__Profile2D + Na__Asset__Mesh3D',
                    'assetData'      => source[:asset],
                    'units'          => 'mm'
                }
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reshaping (profile_edit)
# -----------------------------------------------------------------------------

        # Returns the source with a reshaped COPY of its asset, marked local
        # (the library file is never touched here).
        def self.na_apply_profile_edit(source, edit, local_name = nil)
            return source unless edit.is_a?(Hash) && !edit.empty?
            asset = self.na_deep_copy(source[:asset])
            notes = self.Na__McpShape__Apply(asset, edit)
            name  = local_name.to_s.strip
            name  = source[:name].to_s if name.empty?
            source.merge(asset: asset, local: true, kind: "#{source[:kind]}+edit", name: name, edits: notes, record: nil)
        rescue ArgumentError => error
            self.na_refuse('invalid_params', "profile_edit: #{error.message}", 'See the profile_edit description: scale, size, stretch, flip, datum.')
        end

        # FUNCTION | Reshape a unified asset in place (pure data; offline tested)
        # ------------------------------------------------------------
        # Returns a list of what was done. Raises ArgumentError on a bad edit.
        def self.Na__McpShape__Apply(asset, edit)
            notes = []
            unknown = edit.keys.map(&:to_s) - %w[scale size keep_aspect stretch flip datum]
            raise ArgumentError, "unknown key(s) #{unknown.join(', ')}" unless unknown.empty?

            if edit.key?('scale')
                factors = edit['scale'].is_a?(Array) ? edit['scale'] : [edit['scale'], edit['scale']]
                raise ArgumentError, 'scale is a number or [across, up]' unless factors.length == 2 && factors.all? { |value| value.is_a?(Numeric) && value > 0 }
                self.Na__McpShape__Scale(asset, factors[0].to_f, factors[1].to_f)
                notes << "scaled #{factors[0]} across, #{factors[1]} up"
            end

            if edit.key?('size')
                size = edit['size']
                raise ArgumentError, 'size is {width, height} in mm' unless size.is_a?(Hash) && (size.key?('width') || size.key?('height'))
                extent = self.Na__McpShape__Extent(asset)
                raise ArgumentError, 'the profile has no extent to size' unless extent
                width  = extent[1] - extent[0]
                height = extent[3] - extent[2]
                sy = size['width']  ? size['width'].to_f / width : nil
                sz = size['height'] ? size['height'].to_f / height : nil
                raise ArgumentError, 'size must be positive' if [sy, sz].compact.any? { |value| !(value > 0) }
                if edit['keep_aspect'] == true
                    factor = sy || sz
                    sy = sz = factor
                end
                self.Na__McpShape__Scale(asset, sy || 1.0, sz || 1.0)
                notes << "sized to #{size['width'] || width.round(3)} x #{size['height'] || height.round(3)} mm"
            end

            Array(edit['stretch']).each_with_index do |cut, index|
                raise ArgumentError, "stretch[#{index}] is {axis, at, by, side}" unless cut.is_a?(Hash)
                axis = { 'y' => 'y', 'width' => 'y', 'across' => 'y', 'z' => 'z', 'height' => 'z', 'up' => 'z' }[cut['axis'].to_s]
                raise ArgumentError, "stretch[#{index}].axis is y (across) or z (up)" unless axis
                raise ArgumentError, "stretch[#{index}] needs numeric at and by (mm)" unless cut['at'].is_a?(Numeric) && cut['by'].is_a?(Numeric)
                side = cut['side'].to_s.empty? ? 'above' : cut['side'].to_s
                raise ArgumentError, "stretch[#{index}].side is above or below" unless %w[above below].include?(side)
                moved = self.Na__McpShape__Stretch(asset, axis, cut['at'].to_f, cut['by'].to_f, side)
                notes << "stretched #{axis} by #{cut['by']} mm #{side} #{cut['at']} (#{moved} vertices moved)"
            end

            if edit['flip'] == true
                raise ArgumentError, 'the profile has no geometry to flip' unless Na__EditProfile__GeometryWriter.Na__GeometryWriter__FlipHorizontal(asset)
                notes << 'flipped left to right about the datum'
            end

            if edit.key?('datum')
                datum = edit['datum']
                raise ArgumentError, 'datum is [y, z] in mm: the profile point that becomes 0,0' unless datum.is_a?(Array) && datum.length == 2 && datum.all? { |value| value.is_a?(Numeric) }
                unless datum[0].to_f.zero? && datum[1].to_f.zero?
                    raise ArgumentError, 'the profile has no geometry to move' unless Na__EditProfile__DatumWriter.Na__DatumWriter__ReDatum(asset, datum[0].to_f, datum[1].to_f)
                    notes << "datum moved to [#{datum[0]}, #{datum[1]}]"
                end
            end
            asset['meta']['lastUpdated'] = Time.now.strftime('%d-%b-%Y') if asset['meta'].is_a?(Hash)
            notes
        end
        # ---------------------------------------------------------------

        # [min_y, max_y, min_z, max_z] of the Profile2D vertices, or nil.
        def self.Na__McpShape__Extent(asset)
            vertices = Array(asset.dig('Na__Asset__Profile2D', 'Na__Geometry__Vertices')).select { |vertex| vertex.is_a?(Hash) }
            return nil if vertices.empty?
            ys = vertices.map { |vertex| vertex['PosY_mm'].to_f }
            zs = vertices.map { |vertex| vertex['PosZ_mm'].to_f }
            [ys.min, ys.max, zs.min, zs.max]
        end

        # Multiplies every coordinate: Profile2D (PosY, PosZ), Mesh3D (PosX =
        # profile Y, PosY = profile Z), its bounding box and the audit
        # dimensions. A uniform scale scales arc radii; any other drops them.
        def self.Na__McpShape__Scale(asset, sy, sz)
            self.Na__McpShape__MapPoints(asset) { |y, z| [y * sy, z * sz] }
            uniform = (sy - sz).abs < 1e-12
            Array(asset.dig('Na__Asset__Profile2D', 'Na__Geometry__Curves')).each do |curve|
                next unless curve.is_a?(Hash) && curve.key?('Radius_mm')
                if uniform
                    curve['Radius_mm'] = (curve['Radius_mm'].to_f * sy).round(6)
                else
                    curve.delete('Radius_mm')
                end
            end
            true
        end

        # Points beyond the cut (above: coordinate >= at; below: <= at) move by
        # 'by' along the axis. Returns how many Profile2D vertices moved. An arc
        # with vertices on both sides is no longer circular: its radius goes.
        def self.Na__McpShape__Stretch(asset, axis, at, by, side)
            tolerance = 1e-6
            beyond = side == 'above' ? ->(value) { value >= at - tolerance } : ->(value) { value <= at + tolerance }
            index = axis == 'y' ? 0 : 1

            moved_ids = {}
            Array(asset.dig('Na__Asset__Profile2D', 'Na__Geometry__Vertices')).each do |vertex|
                next unless vertex.is_a?(Hash)
                value = axis == 'y' ? vertex['PosY_mm'].to_f : vertex['PosZ_mm'].to_f
                moved_ids[vertex['VertexId'].to_s] = beyond.call(value)
            end
            self.Na__McpShape__MapPoints(asset) do |y, z|
                point = [y, z]
                point[index] += by if beyond.call(point[index])
                point
            end
            Array(asset.dig('Na__Asset__Profile2D', 'Na__Geometry__Curves')).each do |curve|
                next unless curve.is_a?(Hash)
                flags = Array(curve['VertexIds']).map { |id| moved_ids[id.to_s] }.compact.uniq
                curve.delete('Radius_mm') if flags.length > 1
            end
            moved_ids.values.count(true)
        end

        # Applies (y, z) -> (y', z') to every coordinate pair the asset holds,
        # then recomputes the Mesh3D bounding box from its vertices.
        def self.Na__McpShape__MapPoints(asset)
            Array(asset.dig('Na__Asset__Profile2D', 'Na__Geometry__Vertices')).each do |vertex|
                next unless vertex.is_a?(Hash)
                y, z = yield(vertex['PosY_mm'].to_f, vertex['PosZ_mm'].to_f)
                vertex['PosY_mm'] = y.round(6)
                vertex['PosZ_mm'] = z.round(6)
            end
            mesh = asset['Na__Asset__Mesh3D']
            if mesh.is_a?(Hash)
                vertices = Array(mesh['Na__Geometry__Vertices']).select { |vertex| vertex.is_a?(Hash) }
                vertices.each do |vertex|
                    y, z = yield(vertex['PosX_mm'].to_f, vertex['PosY_mm'].to_f)
                    vertex['PosX_mm'] = y.round(6)
                    vertex['PosY_mm'] = z.round(6)
                end
                box = mesh['Na__Geometry__BoundingBox']
                if box.is_a?(Hash) && !vertices.empty?
                    box['Na__Geometry__MinX_mm'] = vertices.map { |vertex| vertex['PosX_mm'] }.min
                    box['Na__Geometry__MaxX_mm'] = vertices.map { |vertex| vertex['PosX_mm'] }.max
                    box['Na__Geometry__MinY_mm'] = vertices.map { |vertex| vertex['PosY_mm'] }.min
                    box['Na__Geometry__MaxY_mm'] = vertices.map { |vertex| vertex['PosY_mm'] }.max
                end
            end
            Array(asset.dig('Na__Asset__Annotations2D', 'Na__Annotation__Dimensions')).each do |dimension|
                next unless dimension.is_a?(Hash)
                %w[Start End].each do |end_name|
                    y, z = yield(dimension["#{end_name}Y_mm"].to_f, dimension["#{end_name}Z_mm"].to_f)
                    dimension["#{end_name}Y_mm"] = y.round(6)
                    dimension["#{end_name}Z_mm"] = z.round(6)
                end
            end
            asset
        end

# endregion -------------------------------------------------------------------

    end # module Na__McpOperations
end # module Na__ProfileTools__ProfilePathTracer

# =============================================================================
# END OF FILE
# =============================================================================
