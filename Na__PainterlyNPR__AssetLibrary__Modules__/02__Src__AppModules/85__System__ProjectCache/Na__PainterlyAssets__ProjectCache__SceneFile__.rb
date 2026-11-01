# =============================================================================
# NA PAINTERLYNPR ASSETS - PROJECT CACHE - SCENE FILE
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ProjectCache__SceneFile__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__SceneFile
# PURPOSE    : The scene the NPR Viewport hands to PainterlyNPR: every cached
#              GLB with its part, use and role, the engine objects made from
#              their mesh nodes, and one placement into the engine's world.
#              The local twin of ValeVision AURA's scene import (scene API
#              1.2.0), so SketchUp's NPR view starts from what AURA would draw.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - A FILE'S PART comes from its name, as the GLB builder writes it
#   (<prefix>__TrueVision__<Group>__<Variant>__<Kind>Model__.glb, or
#   <prefix>__Storey__<Floor>__<Element>__<Kind>Model__.glb). The first rule
#   in the config (nprViewport.sceneImport.rules: AURA's table, with rows for
#   storey files) whose every condition the file meets gives its Use (Draw,
#   SourceLinework, Ignore) and its objects' starting Role, Category and
#   material class; a component node's type word can override them.
# - OBJECT IDS NEVER MOVE (the engine's rule: new content is appended, so
#   nothing already drawn reshuffles its strokes): a node keeps its Id while
#   its file and name, or its SketchUp persistent id, are found again; a new
#   node takes the next free Id; a node that has gone stays as Missing, so its
#   Id is never reused. The engine needs them 1, 2, 3 ... in order.
# - THE PLACEMENT centres the focal buildings' footprint on the engine's origin
#   (its lawn and its sun's square look there), the ground level unchanged and
#   no turn: SketchUp's front (-green) is already the engine's +Z. It is set
#   once and kept, so the view does not jump as the model is edited, unless the
#   building has moved further than recentreM from the origin.
# - Pure Ruby over the files: nothing here touches the model.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__SceneFile

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_SCENE_SCHEMA  = 'Na__PainterlyAssets__NprScene'.freeze                       unless defined?(NA_SCENE_SCHEMA)
        NA_KINDS         = { 'MeshModel' => 'Mesh', 'LineworkModel' => 'Linework' }.freeze unless defined?(NA_KINDS)
        NA_PERSISTENT_ID = /_ID(\d+)\z/.freeze                                          unless defined?(NA_PERSISTENT_ID)
        NA_ID_PART       = /\A_?\d*_?ID\d+\z/.freeze                                    unless defined?(NA_ID_PART)
        NA_FALLBACK_RULE = { 'Use' => 'Draw', 'Role' => 'Architecture', 'Category' => 'Wall', 'Material' => 'Render' }.freeze unless defined?(NA_FALLBACK_RULE)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Building the Scene
    # -------------------------------------------------------------------------

        # FUNCTION | The Scene From the Cache's GLB Files, Keeping the Previous One's Ids
        # ------------------------------------------------------------
        # @param folder [String] the project's cache folder
        # @param file_names [Array<String>] the GLBs the manifest holds
        # @param previous [Hash, nil] the scene now
        # @return [Hash] the scene (not yet written)
        def self.Na__Scene__Build(folder, file_names, previous = nil)
            rules     = self.na_rules
            names     = Array(file_names).sort
            files     = []
            fresh     = []
            focal     = nil
            building  = nil

            names.each do |file_name|
                part = self.Na__Scene__ParseFile(file_name)
                next unless part

                path = File.join(folder, file_name)
                next unless File.file?(path)

                json   = Na__GlbReader.Na__Glb__Read(path)['json']
                lo, hi = self.Na__Scene__Bounds(json)
                rule   = self.Na__Scene__FileRule(part, rules['Rules'])
                use    = rule['Use'] || 'Draw'
                twin   = part['Kind'] == 'Mesh' ? file_name.sub('__MeshModel__', '__LineworkModel__') : file_name.sub('__LineworkModel__', '__MeshModel__')
                files << {
                    'ModelFile__Id'       => part['Id'],
                    'ModelFile__FileName' => file_name,
                    'ModelFile__Group'    => part['Group'],
                    'ModelFile__Variant'  => part['Variant'],
                    'ModelFile__Kind'     => part['Kind'],
                    'ModelFile__Use'      => use,
                    'ModelFile__Twin'     => names.include?(twin) && twin != file_name ? self.Na__Scene__ParseFile(twin)['Id'] : nil,
                    'ModelFile__Role'     => use == 'Draw' ? rule['Role'] : nil,
                    'ModelFile__Bytes'    => File.size(path),
                    'ModelFile__Nodes'    => Array(json['nodes']).length,
                    'ModelFile__BoundsM'  => { 'Min' => lo, 'Max' => hi }
                }
                next unless use == 'Draw' && part['Kind'] == 'Mesh'

                Array(json['nodes']).each do |node|
                    next unless node.is_a?(Hash) && node.key?('mesh')
                    made = self.Na__Scene__NodeObject(node['name'].to_s, part['Id'], rule, rules['ComponentRules'], rules['SkipNodes'], node['mesh'])
                    fresh << made if made
                end
                focal    = self.na_grow(focal, lo, hi)    if rule['Role'] == 'Focal'
                building = self.na_grow(building, lo, hi) if rule['Role'] == 'Architecture'
            end

            {
                'NprScene__Meta'           => {
                    'Schema'        => NA_SCENE_SCHEMA,
                    'SchemaVersion' => 1,
                    'Revision'      => previous.is_a?(Hash) ? previous.dig('NprScene__Meta', 'Revision').to_i + 1 : 1,
                    'UpdatedIso'    => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
                    'Note'          => 'Made by Na PainterlyNPR Assets from the GLB builder\'s files in this folder, by ValeVision AURA\'s import rules: the scene the NPR Viewport hands to PainterlyNPR (ScenePackage GlbBase). Object Ids never move.'
                },
                'NprScene__ModelPlacement' => self.na_placement(previous, focal, building),
                'NprScene__ModelFiles'     => files,
                'NprScene__Objects'        => self.na_objects(fresh, previous)
            }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Import Rules: a File's Part, Use and Role; a Node's Object
    # -------------------------------------------------------------------------

        # FUNCTION | A File's Part From Its Name: { Id, Group, Variant, Kind }, or nil
        # ------------------------------------------------------------
        # 'Thrower__TrueVision__MainBuildingModel__Proposed__MeshModel__.glb'
        # -> Id 'MainBuildingModel__Proposed__MeshModel', Group 'MainBuildingModel'.
        def self.Na__Scene__ParseFile(name)
            return nil unless name.to_s.downcase.end_with?('.glb')
            tokens = name.to_s[0...-4].gsub(/\A_+|_+\z/, '').split('__')
            rest   = tokens.drop(1)                                                 # <-- tokens[0] is the project's prefix
            rest   = rest.drop(1) if rest.first == 'TrueVision' || rest.first.to_s =~ /\A\d+\z/
            return nil if rest.length < 2 || !NA_KINDS.key?(rest.last)
            variant = rest[1...-1].join('__')
            { 'Id' => rest.join('__'), 'Group' => rest.first, 'Variant' => variant.empty? ? nil : variant, 'Kind' => NA_KINDS[rest.last] }
        end
        # ---------------------------------------------------------------

        # The first rule every condition of which the file meets
        def self.Na__Scene__FileRule(part, file_rules)
            variant = part['Variant'].to_s
            Array(file_rules).each do |rule|
                next unless rule.is_a?(Hash)
                next if rule['Match']           && !part['Id'].include?(rule['Match'])
                next if rule['Kind']            && rule['Kind'] != part['Kind']
                next if rule['Group']           && rule['Group'] != part['Group']
                next if rule['VariantStarts']   && !variant.start_with?(rule['VariantStarts'])
                next if rule['VariantContains'] && !variant.include?(rule['VariantContains'])
                return rule
            end
            NA_FALLBACK_RULE
        end

        # FUNCTION | One Object From One Mesh Node (no Id yet), or nil for a node never drawn
        # ------------------------------------------------------------
        def self.Na__Scene__NodeObject(node_name, file_id, rule, component_rules, skip, mesh_index)
            return nil if node_name.empty? || (skip && node_name =~ skip)
            pid      = node_name[NA_PERSISTENT_ID, 1]
            category = rule['Category'] || 'Wall'
            material = rule['Material'] || 'Render'
            role     = rule['Role'] || 'Architecture'
            if node_name.include?('::')                                             # <-- A flattened tag: '20__ProposedBuilding::Default'
                name = self.na_humanise(node_name.split('::').first.split('__').last.to_s)
            else                                                                    # <-- An instanced component: '10_2001__Column__StopChamfer__...___ID32059153'
                parts     = node_name.split('__').reject { |t| t.empty? || t =~ NA_ID_PART }
                type_word = parts[1].to_s
                Array(component_rules).each do |comp|
                    next unless comp.is_a?(Hash) && comp['Type'] == type_word
                    category = comp['Category'] || category
                    material = comp['Material'] || material
                    role     = comp['Role'] || role
                    break
                end
                name = parts.drop(1).join(' ') + (pid ? ", ID#{pid}" : '')
                name = node_name if name.strip.empty?
            end
            {
                'Object__Name'         => name,
                'Object__ModelFile'    => file_id,
                'Object__Node'         => node_name,
                'Object__Mesh'         => mesh_index,
                'Object__PersistentId' => pid ? pid.to_i : nil,
                'Object__Category'     => category,
                'Object__Material'     => material,
                'Object__Role'         => role
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | A File's Contents in Its Own Metres, Node Transforms Applied: [[min], [max]]
        # ------------------------------------------------------------
        # From each primitive's POSITION min and max (glTF requires them), as
        # AURA's import measures a file.
        def self.Na__Scene__Bounds(json)
            nodes     = Array(json['nodes'])
            meshes    = Array(json['meshes'])
            accessors = Array(json['accessors'])
            lo = [Float::INFINITY] * 3
            hi = [-Float::INFINITY] * 3
            visit = lambda do |index, parent, depth|
                node = nodes[index]
                return unless node.is_a?(Hash) && depth < Na__GlbReader::NA_MAX_NODE_DEPTH
                world = Na__GlbReader.na_multiply(parent, Na__GlbReader.na_node_matrix(node))
                if node.key?('mesh') && meshes[node['mesh']].is_a?(Hash)
                    Array(meshes[node['mesh']]['primitives']).each do |primitive|
                        accessor = accessors[primitive.dig('attributes', 'POSITION').to_i]
                        next unless accessor.is_a?(Hash) && accessor['min'].is_a?(Array) && accessor['max'].is_a?(Array)
                        [accessor['min'][0], accessor['max'][0]].product([accessor['min'][1], accessor['max'][1]], [accessor['min'][2], accessor['max'][2]]).each do |corner|
                            p = Na__GlbReader.na_transform(world, corner)
                            3.times { |k| lo[k] = p[k] if p[k] < lo[k]; hi[k] = p[k] if p[k] > hi[k] }
                        end
                    end
                end
                Array(node['children']).each { |child| visit.call(child, world, depth + 1) }
            end
            scenes = Array(json['scenes'])
            roots  = scenes.empty? ? (0...nodes.length).to_a : Array((scenes[json['scene'].to_i] || {})['nodes'])
            roots.each { |root| visit.call(root, Na__GlbReader::NA_IDENTITY, 0) }
            return [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]] if lo[0] == Float::INFINITY
            [lo.map { |v| v.round(3) }, hi.map { |v| v.round(3) }]
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_rules
            section = Na__ConfigLoader.Na__Config__Get('nprViewport', 'sceneImport') || {}
            skip    = section['skipNodes'].to_s
            {
                'Rules'          => Array(section['rules']),
                'ComponentRules' => Array(section['componentRules']),
                'SkipNodes'      => skip.empty? ? nil : Regexp.new(skip)
            }
        end

        def self.na_grow(box, lo, hi)
            return [lo.dup, hi.dup] unless box
            [box[0].zip(lo).map { |a, b| [a, b].min }, box[1].zip(hi).map { |a, b| [a, b].max }]
        end

        # Ids kept for every node found again (by file, node and which of its
        # name's nodes it is, then by persistent id), the next free one for a new
        # node, a gone node marked Missing. A file repeats node names (a tag's
        # buckets, a component placed twice): the k-th keeps the k-th's Id, as the
        # engine's GlbBase takes the k-th node of a repeated name.
        def self.na_objects(fresh, previous)
            old = previous.is_a?(Hash) ? Array(previous['NprScene__Objects']) : []
            return fresh.each_with_index.map { |o, i| { 'Object__Id' => i + 1 }.merge(o) } if old.empty?

            by_node = self.na_occurrences(old.reject { |o| o['Object__Missing'] }).each_with_object({}) { |(o, key), h| h[key] ||= o }
            by_pid  = old.each_with_object({}) { |o, h| h[o['Object__PersistentId']] ||= o if o['Object__PersistentId'] }
            kept    = {}
            next_id = old.map { |o| o['Object__Id'].to_i }.max.to_i + 1
            objects = self.na_occurrences(fresh).map do |made, key|
                match = by_node[key]
                match = by_pid[made['Object__PersistentId']] if (match.nil? || kept[match['Object__Id']]) && made['Object__PersistentId']
                if match && !kept[match['Object__Id']]
                    kept[match['Object__Id']] = true
                    { 'Object__Id' => match['Object__Id'] }.merge(made)
                else
                    record = { 'Object__Id' => next_id }.merge(made)
                    next_id += 1
                    record
                end
            end
            old.each do |o|
                next if kept[o['Object__Id']]
                objects << o.merge('Object__Missing' => true)
            end
            objects.sort_by { |o| o['Object__Id'].to_i }
        end

        # Each object with its key: [file, node, which of that name's nodes in the file]
        def self.na_occurrences(list)
            seen = Hash.new(0)
            list.map do |o|
                pair = [o['Object__ModelFile'], o['Object__Node']]
                seen[pair] += 1
                [o, pair + [seen[pair]]]
            end
        end

        # The focal footprint's centre to the origin; kept once set unless the
        # building has wandered past recentreM, so the view never jumps per edit.
        def self.na_placement(previous, focal, building)
            box     = focal || building
            kept    = previous.is_a?(Hash) ? previous['NprScene__ModelPlacement'] : nil
            limit   = Na__ConfigLoader.Na__Config__GetOr(25.0, 'nprViewport', 'sceneImport', 'recentreM').to_f
            if kept.is_a?(Hash) && kept['CentredOn'] != 'None' && kept['OffsetM'].is_a?(Array)
                return kept unless box
                cx = (box[0][0] + box[1][0]) / 2.0 + kept['OffsetM'][0].to_f
                cz = (box[0][2] + box[1][2]) / 2.0 + kept['OffsetM'][2].to_f
                return kept if Math.hypot(cx, cz) <= limit
            end
            cx = box ? ((box[0][0] + box[1][0]) / 2.0).round(3) : 0.0
            cz = box ? ((box[0][2] + box[1][2]) / 2.0).round(3) : 0.0
            {
                'OffsetM'     => [-cx, 0.0, -cz],
                'RotationDeg' => 0.0,
                'FrontFacing' => '+Z',
                'CentredOn'   => focal ? 'Focal' : (building ? 'Architecture' : 'None'),
                'Note'        => 'Every model file, then the camera: turned about +Y by RotationDeg, then moved by OffsetM (metres, the GLB builder\'s glTF axes, x = red, y = blue, z = -green).'
            }
        end

        def self.na_humanise(tag)
            words = tag.to_s.gsub(/(?<=[a-z])(?=[A-Z])/, ' ').split
            words.empty? ? tag.to_s : ([words.first] + words.drop(1).map(&:downcase)).join(' ')
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
