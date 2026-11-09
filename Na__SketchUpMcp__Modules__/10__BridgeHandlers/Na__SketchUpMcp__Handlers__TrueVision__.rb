# =============================================================================
# NA SKETCHUP MCP - HANDLERS - TRUEVISION
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__TrueVision__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__TrueVision
# PURPOSE    : truevision_structure: read a model the way the TrueVision GLB
#              Builder exports it, say what it will skip and why, and list
#              every object so it can be classified, tagged and nested
# CREATED    : 09-Nov-2026 (1.0.18)
#
# THE EXPORTER'S RULES (Na__TrueVision__GlbBuilder__CoreExport__.rb):
# - Only ROOT entities are segmented, by their tag's "NN__" number. Everything
#   nested exports with its root ancestor, whatever its own tag (linetype and
#   excluded tags apart).
# - A root Group/ComponentInstance on a storey tag (90-93, Storey__IsContainer)
#   is a storey container. Several on one storey merge (the first's transform).
# - Inside a storey container only DIRECT child Groups/ComponentInstances whose
#   tag number is in the storey element map (Storey__ElementExportName: 07-09,
#   11-19, 21-29, 60-61) export, one file per storey and element. Loose faces
#   and edges directly in a storey container, and children on any other tag
#   (Untagged included), are skipped without a word.
# - Other root entities on numbered tags go to the flat files (Glb__ExportRange
#   Numbers). Skip ranges (00, 02-06), excluded tags, Untagged and unnumbered
#   tags never export.
# - It reads model.active_entities: a group open at export time hides the rest.
# - Mesh ignores hidden entities and tag visibility; LINEWORK skips hidden
#   entities and tags switched off at export time.
#
# WHERE THE RULES COME FROM:
# The GLB Builder's own Na__ExportConfig__* readers when it has loaded its
# config in this SketchUp (no network call is ever started from here), else the
# Tags SSOT file beside the Plugins folder, read the way the exporter reads it.
#
# =============================================================================

require 'fileutils'

module Na__SketchUpMcp
    module Na__Handlers__TrueVision

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_TAG_NUMBER      = /\A(\d{2})__/.freeze
        NA_LIBRARY_CODE    = /\A\d{2}_[0-9A-Za-z]{1,6}_{1,2}/.freeze  # library components: 18_1101__, 27_50__, 28_LP13__, 94_01_--_
        NA_ASSEMBLY_NAME   = /\A(ADR|AWN)/.freeze                     # Element Assembly Studio doors and windows
        NA_SSOT_TAGS_FILE  = File.expand_path('../../Na__Common__DataLib__CoreSuEntityStandards/Na__DataLib__CoreIndex__Tags__.json', __dir__).freeze
        NA_SITE_PLAN       = /\A\d{2}__SitePlan__/.freeze
        NA_SURVEY_DATUM    = /\A\d{2}__Survey__DatumBenchmark/.freeze
        NA_MESH_SUFFIX     = '__MeshModel__.glb'.freeze
        NA_LINEWORK_SUFFIX = '__LineworkModel__.glb'.freeze
        NA_ORBIT_STEM      = '01__OrbitHelperCube'.freeze
        NA_FACE_BUDGET     = 1_500_000
        NA_NESTED_DEPTH    = 8
        NA_HORIZONTAL      = 0.985                                    # |normal z| above: horizontal (within 10 degrees)
        NA_VERTICAL        = 0.174                                    # |normal z| below: vertical (within 10 degrees)
        NA_SQ_IN_TO_SQ_M   = 0.00064516
        NA_LEVEL_BIN_MM    = 5.0
        NA_LEVEL_MIN_M2    = 0.05                                     # faces smaller than this do not vote for a level

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | truevision_structure
# -----------------------------------------------------------------------------

        def self.Na__Handlers__TrueVision__Structure(params, ctx)
            model = ctx[:model]
            config = na_config(ctx)
            unless config
                raise Na__McpError.new('unsupported', 'The TrueVision export rules could not be read: the GLB Builder has not loaded them and the Tags SSOT file is missing or unreadable.',
                                       "Check #{NA_SSOT_TAGS_FILE}, or open the GLB Builder dialog once so it loads its config.")
            end

            options = na_options(params)
            state = { model: model, ctx: ctx, config: config, options: options, tag_cache: {}, nested_memo: {},
                      budget: NA_FACE_BUDGET, faces_truncated: false, levels: Hash.new(0.0) }
            unless (model.active_path || []).empty?
                ctx[:warnings] << 'A group is open for editing. The GLB Builder reads model.active_entities, so an export now would see only that group: close it before exporting.'
            end

            root = na_read_root(state)
            storeys = na_read_storeys(root[:storeys], state)
            nested = na_nested_category_tags(root, storeys, state)
            files = na_export_files(model, root[:flat], storeys) + na_linetype_files(model, ctx)

            result = {
                'model' => model.title, 'rules_from' => config[:source],
                'mode' => storeys.empty? ? 'flat (no storey containers at the model root)' : 'storeys',
                'file_prefix' => na_prefix(model), 'units' => ctx[:unit],
                'storeys' => storeys.map { |storey| na_storey_report(storey, state) },
                'flat' => na_group_report(root[:flat], state),
                'never_exported_at_root' => na_reason_report(root[:ignored], state),
                'loose_geometry_at_root' => root[:loose],
                'nested_category_tags' => nested,
                'export_files' => files
            }
            result['toggled_off_files'] = root[:toggled_off] unless root[:toggled_off].empty?

            if options[:objects] || options[:save_path]
                objects = na_objects(root, storeys, state)
                result['objects_total'] = objects.length
                if options[:save_path]
                    na_save(options[:save_path], options[:overwrite], result.merge('objects' => objects, 'levels' => na_levels(state)))
                    result['saved_to'] = options[:save_path]
                end
                if options[:objects]
                    page = objects[options[:offset], options[:limit]] || []
                    result['objects'] = page
                    result['next_offset'] = options[:offset] + page.length < objects.length ? options[:offset] + page.length : nil
                end
            end
            result['levels'] = na_levels(state) if options[:analyse]
            result['faces_truncated'] = true if state[:faces_truncated]
            result['summary'] = na_summary(result, root, storeys, nested)
            result
        end

        def self.na_options(params)
            options = {
                max_names: Na__Params.Na__Params__Integer(params, 'max_names', 8, min: 0, max: 200),
                objects: Na__Params.Na__Params__Boolean(params, 'include_objects', false),
                expand_depth: Na__Params.Na__Params__Integer(params, 'expand_depth', 2, min: 0, max: 8),
                analyse: Na__Params.Na__Params__Boolean(params, 'analyse_faces', false),
                limit: Na__Params.Na__Params__Integer(params, 'limit', 40, min: 1, max: 500),
                offset: Na__Params.Na__Params__Integer(params, 'offset', 0, min: 0),
                overwrite: Na__Params.Na__Params__Boolean(params, 'overwrite', false)
            }
            path = Na__Params.Na__Params__String(params, 'save_path', nil)
            if path
                unless File.absolute_path?(path) && path.downcase.end_with?('.json')
                    raise Na__McpError.new('invalid_params', "save_path must be an absolute .json path: #{path}", 'For example C:/Temp/RB05__TrueVisionStructure.json.')
                end

                options[:save_path] = path
            end
            options
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Exporter's Rules
# -----------------------------------------------------------------------------

        def self.na_config(ctx)
            glb = defined?(::TrueVision3D::GlbBuilderUtility) ? ::TrueVision3D::GlbBuilderUtility : nil
            if glb && glb.respond_to?(:Na__ExportConfig__StoreyElementTagMap) && glb.instance_variable_get(:@na_datalib_loaded)
                begin
                    return na_normalise('the TrueVision GLB Builder loaded in this SketchUp', glb.Na__ExportConfig__TagRanges,
                                        glb.Na__ExportConfig__SkipRanges, glb.Na__ExportConfig__StoreyTagMap,
                                        glb.Na__ExportConfig__StoreyElementTagMap, glb.Na__ExportConfig__StoreyTagRange,
                                        glb.Na__ExportConfig__ExclusionPattern, glb.Na__ExportConfig__FullyExcludedTagNames)
                rescue StandardError => error
                    ctx[:warnings] << "The GLB Builder's export config could not be read (#{error.message}); the Tags SSOT file was used."
                end
            end
            na_config_from_ssot(ctx)
        end

        # Mirrors Na__ExportConfig__BuildHashesFromTagEntries, ExportExclusions and meta.skipRanges.
        def self.na_config_from_ssot(ctx)
            return nil unless File.exist?(NA_SSOT_TAGS_FILE)

            data = JSON.parse(File.read(NA_SSOT_TAGS_FILE, encoding: 'UTF-8'))
            library = data['Na__DataLib__CoreIndex__Tags']
            return nil unless library.is_a?(Hash)

            tag_ranges = {}
            storey_map = {}
            element_map = {}
            storey_range = []
            library.each_value do |section|
                next unless section.is_a?(Hash)

                section.each_value do |entry|
                    next unless entry.is_a?(Hash)

                    numbers = entry['Glb__ExportRangeNumbers']
                    stem = entry['Glb__ExportFileNameStem']
                    tag_ranges[stem] = numbers if stem && numbers.is_a?(Array) && !numbers.empty?
                    if entry['Storey__IsContainer']
                        number = entry['Tag__SketchUpName'].to_s[NA_TAG_NUMBER, 1]
                        if number
                            storey_range << number.to_i
                            storey_map[number.to_i] = entry['Storey__ContainerExportName'] if entry['Storey__ContainerExportName']
                        end
                    end
                    element = entry['Storey__ElementExportName']
                    numbers.each { |value| element_map[value] = element } if element && numbers.is_a?(Array)
                end
            end
            return nil if tag_ranges.empty?

            exclusions = data['ExportExclusions'].is_a?(Hash) ? data['ExportExclusions'] : {}
            pattern = exclusions['PatternExclusionRegex'] ? Regexp.new(exclusions['PatternExclusionRegex']) : nil
            meta = data['meta'].is_a?(Hash) ? data['meta'] : {}
            skip = meta['skipRanges'].is_a?(Array) ? meta['skipRanges'] : [0, 2, 3, 4, 5, 6]
            na_normalise("the Tags SSOT file (#{File.basename(NA_SSOT_TAGS_FILE)} #{meta['version']})", tag_ranges, skip, storey_map,
                         element_map, storey_range, pattern, exclusions['FullyExcludedTagNames'])
        rescue StandardError => error
            ctx[:warnings] << "The Tags SSOT file could not be read: #{error.message}"
            nil
        end

        def self.na_normalise(source, tag_ranges, skip, storey_map, element_map, storey_range, pattern, fully_excluded)
            {
                source: source,
                tag_ranges: tag_ranges.map { |stem, range| [stem.to_s, (range.is_a?(Range) ? range.to_a : Array(range)).map(&:to_i)] },
                skip: Array(skip).map(&:to_i),
                storey_map: storey_map.each_with_object({}) { |(number, name), lookup| lookup[number.to_i] = name.to_s },
                element_map: element_map.each_with_object({}) { |(number, name), lookup| lookup[number.to_i] = name.to_s },
                storey_range: Array(storey_range).map(&:to_i),
                pattern: pattern,
                fully_excluded: Array(fully_excluded).map(&:to_s)
            }
        end

        # What the exporter makes of one tag. Cached per tag for the call.
        def self.na_tag_info(layer, state)
            state[:tag_cache][layer] ||= begin
                config = state[:config]
                raw = layer.name.to_s
                number = raw[NA_TAG_NUMBER, 1]
                number = number.to_i if number
                info = { name: Na__EntityResolver.Na__EntityResolver__TagDisplayName(layer), raw: raw, number: number,
                         untagged: layer == state[:model].layers[0] }
                info[:excluded] = !info[:untagged] && ((config[:pattern] && raw =~ config[:pattern]) || raw =~ NA_SITE_PLAN ||
                                                       raw =~ NA_SURVEY_DATUM || config[:fully_excluded].include?(raw)) ? true : false
                if number
                    info[:skip] = config[:skip].include?(number)
                    info[:storey] = config[:storey_range].include?(number) ? config[:storey_map][number] : nil
                    info[:element] = config[:element_map][number]
                    hit = config[:tag_ranges].find { |_stem, numbers| numbers.include?(number) }
                    info[:stem] = hit ? hit[0] : nil
                end
                info
            end
        end

        def self.na_number_text(number)
            format('%02d', number.to_i)
        end

        def self.na_root_reason(info, instance)
            return 'untagged' if info[:untagged]
            return 'excluded tag' if info[:excluded]
            return 'tag has no NN__ number' unless info[:number]
            return "skip range #{na_number_text(info[:number])} (helper tags never export)" if info[:skip]
            return 'storey tag on loose geometry (only a group or component can be a storey container)' if info[:storey] && !instance
            return nil if info[:stem] || info[:storey]

            "no export file for tag number #{na_number_text(info[:number])}"
        end

        def self.na_child_reason(info)
            return 'untagged' if info[:untagged]
            return 'excluded tag' if info[:excluded]
            return 'tag has no NN__ number' unless info[:number]
            return nil if info[:element]
            return 'storey tag inside a storey (storey tags count only at the model root)' if info[:storey]

            "tag #{na_number_text(info[:number])} is not a storey element tag"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reading the Model as the Exporter Does
# -----------------------------------------------------------------------------

        def self.na_read_root(state)
            model = state[:model]
            flat = {}
            storeys = {}
            ignored = Hash.new { |lookup, key| lookup[key] = [] }
            loose = Hash.new(0)
            model.entities.each do |entity|
                next unless entity.respond_to?(:layer)

                instance = Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                drawable = instance || entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
                info = na_tag_info(entity.layer, state)
                if instance && !info[:excluded] && info[:storey]
                    (storeys[info[:storey]] ||= []) << entity
                elsif drawable && !info[:excluded] && info[:number] && !info[:skip] && info[:stem]
                    (flat[info[:stem]] ||= []) << entity
                elsif instance
                    ignored[na_root_reason(info, true)] << entity
                elsif drawable
                    loose["#{Na__EntityResolver.Na__EntityResolver__TypeName(entity)} (#{na_root_reason(info, false)})"] += 1
                end
            end
            { flat: flat, storeys: storeys, ignored: ignored, loose: loose, toggled_off: na_toggled_off(model) }
        end

        # The GLB Builder's per-model export toggles: key 'deselected', a JSON array of file names.
        def self.na_toggled_off(model)
            raw = model.get_attribute('Na__TrueVision__GlbBuilder__ExportSelection', 'deselected')
            return [] if raw.nil? || raw.to_s.empty?

            names = raw.is_a?(Array) ? raw : JSON.parse(raw.to_s)
            names.map(&:to_s).first(60)
        rescue StandardError
            []
        end

        # [{ name:, containers: [..], elements: { 'ProposedWalls' => [[child, container], ..] }, skipped: [[child, container, reason]], loose: {} }]
        def self.na_read_storeys(storey_roots, state)
            order = state[:config][:storey_map].sort_by { |number, _name| number }.map { |_number, name| name }
            storey_roots.sort_by { |name, _list| order.index(name) || 99 }.map do |name, containers|
                storey = { name: name, containers: containers, elements: {}, skipped: [], loose: Hash.new(0) }
                containers.each do |container|
                    container.definition.entities.each do |child|
                        next unless child.respond_to?(:layer)

                        unless Na__EntityResolver.Na__EntityResolver__IsInstance(child)
                            storey[:loose][Na__EntityResolver.Na__EntityResolver__TypeName(child)] += 1 if child.is_a?(Sketchup::Face) || child.is_a?(Sketchup::Edge)
                            next
                        end
                        info = na_tag_info(child.layer, state)
                        reason = na_child_reason(info)
                        if reason
                            storey[:skipped] << [child, container, reason]
                        else
                            (storey[:elements][info[:element]] ||= []) << [child, container]
                        end
                    end
                end
                na_check_merged_transforms(storey, state)
                storey
            end
        end

        def self.na_check_merged_transforms(storey, state)
            return if storey[:containers].length < 2

            first = storey[:containers].first.transformation.to_a.map { |value| value.to_f.round(6) }
            differing = storey[:containers].drop(1).reject { |container| container.transformation.to_a.map { |value| value.to_f.round(6) } == first }
            state[:ctx][:warnings] << "#{storey[:name]} has #{storey[:containers].length} root containers; the exporter merges them with the first one's transform." if differing.empty?
            return if differing.empty?

            state[:ctx][:warnings] << "#{storey[:name]}: #{differing.length} of its #{storey[:containers].length} containers have a different transform. " \
                                      'The exporter uses the first container\'s for all, so their contents will land in the wrong place.'
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tags Nested Inside Exported Elements
# -----------------------------------------------------------------------------

        # Numbered category tags (elements, flat files, storeys) on objects INSIDE an exported
        # element: the exporter files them with the element, whatever their own tag says.
        def self.na_nested_category_tags(root, storeys, state)
            config = state[:config]
            category = (config[:element_map].keys + config[:storey_range] + config[:tag_ranges].flat_map { |_stem, numbers| numbers }).uniq - [1]
            findings = Hash.new { |lookup, key| lookup[key] = { 'count' => 0, 'examples' => [] } }
            exported = root[:flat].values.flatten.select { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
            exported += storeys.flat_map { |storey| storey[:elements].values.flatten(1).map(&:first) }
            exported.each do |element|
                own = na_tag_info(element.layer, state)[:raw]
                na_nested_tags_of(element.definition, state, category).each do |tag_name, entry|
                    next if tag_name == own

                    key = "#{tag_name} inside #{own}"
                    findings[key]['count'] += entry[:count]
                    next if findings[key]['examples'].length >= 3

                    findings[key]['examples'] << { 'element_id' => element.persistent_id, 'element' => Na__EntityResolver.Na__EntityResolver__DisplayName(element),
                                                   'nested' => entry[:example] }
                end
            end
            findings.map { |key, entry| { 'tags' => key }.merge(entry) }.sort_by { |entry| -entry['count'] }
        end

        # { tag_name => { count:, example: } } for every nested instance on a category tag, memoised per definition.
        def self.na_nested_tags_of(definition, state, category, depth = 0)
            memo = state[:nested_memo]
            return memo[definition] if memo.key?(definition)
            return {} if depth > NA_NESTED_DEPTH

            found = {}
            definition.entities.each do |child|
                next unless Na__EntityResolver.Na__EntityResolver__IsInstance(child)

                info = na_tag_info(child.layer, state)
                if info[:number] && category.include?(info[:number]) && !info[:excluded]
                    entry = (found[info[:raw]] ||= { count: 0, example: nil })
                    entry[:count] += 1
                    entry[:example] ||= Na__EntityResolver.Na__EntityResolver__DisplayName(child)
                end
                na_nested_tags_of(child.definition, state, category, depth + 1).each do |tag_name, entry|
                    merged = (found[tag_name] ||= { count: 0, example: nil })
                    merged[:count] += entry[:count]
                    merged[:example] ||= entry[:example]
                end
            end
            memo[definition] = found
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Export File Plan
# -----------------------------------------------------------------------------

        # GLB Builder: prefix = the file name up to its first "__" when that part has no "_".
        def self.na_prefix(model)
            name = File.basename(model.path.to_s)
            match = name.match(/\A([^_]+)__/)
            match ? "#{match[1]}__" : ''
        end

        def self.na_export_files(model, flat, storeys)
            prefix = na_prefix(model)
            files = []
            flat.each_key do |stem|
                files << "#{prefix}#{stem}#{NA_MESH_SUFFIX}"
                files << "#{prefix}#{stem}#{NA_LINEWORK_SUFFIX}" unless stem == NA_ORBIT_STEM
            end
            storeys.each do |storey|
                storey[:elements].each_key do |element|
                    files << "#{prefix}#{storey[:name]}__#{element}#{NA_MESH_SUFFIX}"
                    files << "#{prefix}#{storey[:name]}__#{element}#{NA_LINEWORK_SUFFIX}"
                end
            end
            files
        end

        # 1.0.21: the linetype linework GLBs (one per 02__Linetype__ tag holding
        # edges, e.g. ...TrueVision__Linetype__DoorSwings__LineworkModel__.glb).
        # Only the GLB Builder's own walk can plan them, so they are listed
        # when it is loaded here; SK02's 1.0.18 count was one short (37 of 38).
        def self.na_linetype_files(model, ctx)
            builder = defined?(::TrueVision3D::GlbBuilderUtility) ? ::TrueVision3D::GlbBuilderUtility : nil
            if builder && builder.respond_to?(:Na__Linetype__PlanExport) && builder.respond_to?(:Na__Helpers__ExtractProjectPrefix)
                plan = builder.Na__Linetype__PlanExport(model, builder.Na__Helpers__ExtractProjectPrefix(model))
                return Array(plan).map { |row| row[:filename].to_s }.reject(&:empty?)
            end
            if model.layers.any? { |layer| layer.name.start_with?('02__Linetype__') }
                ctx[:warnings] << 'Linetype linework GLBs (02__Linetype__ tags) are not counted: the GLB Builder is not loaded here. truevision_export {action: "manifest"} lists every file.'
            end
            []
        rescue StandardError => error
            ctx[:warnings] << "Linetype linework GLBs could not be planned (#{error.message}); truevision_export {action: \"manifest\"} lists every file."
            []
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Reports
# -----------------------------------------------------------------------------

        def self.na_label(entity)
            label = Na__EntityResolver.Na__EntityResolver__DisplayName(entity)
            label.empty? ? Na__EntityResolver.Na__EntityResolver__TypeName(entity) : label
        end

        def self.na_list(entities, state)
            cap = state[:options][:max_names]
            instances = entities.select { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) }
            report = { 'count' => entities.length }
            report['loose'] = entities.length - instances.length if instances.length < entities.length
            report['names'] = instances.first(cap).map { |entity| "#{na_label(entity)} [#{entity.persistent_id}]" } if cap > 0
            report['more'] = instances.length - cap if cap > 0 && instances.length > cap
            report
        end

        def self.na_group_report(groups, state)
            groups.each_with_object({}) { |(stem, entities), report| report[stem] = na_list(entities, state) }
        end

        def self.na_reason_report(groups, state)
            groups.each_with_object({}) { |(reason, entities), report| report[reason] = na_list(entities, state) }
        end

        def self.na_storey_report(storey, state)
            model = state[:model]
            report = {
                'storey' => storey[:name],
                'containers' => storey[:containers].map do |container|
                    world = Na__Serializer.Na__Serializer__ToWorld(state[:ctx], [])
                    corners = Na__Serializer.Na__Serializer__TightWorldBounds(container, state[:ctx], world)
                    entry = { 'id' => container.persistent_id, 'name' => na_label(container), 'tag' => na_tag_info(container.layer, state)[:name] }
                    if corners
                        entry['z_min'] = Na__Units.Na__Units__FromInches(corners[0][2], state[:ctx][:unit])
                        entry['z_max'] = Na__Units.Na__Units__FromInches(corners[1][2], state[:ctx][:unit])
                    end
                    entry
                end,
                'elements' => storey[:elements].each_with_object({}) { |(element, pairs), lookup| lookup[element] = na_list(pairs.map(&:first), state) }
            }
            unless storey[:skipped].empty?
                grouped = storey[:skipped].group_by { |_child, _container, reason| reason }
                report['skipped'] = grouped.each_with_object({}) { |(reason, rows), lookup| lookup[reason] = na_list(rows.map(&:first), state) }
            end
            report['loose_geometry_skipped'] = storey[:loose] unless storey[:loose].empty?
            report
        end

        def self.na_summary(result, root, storeys, nested)
            parts = []
            if storeys.empty?
                parts << 'Flat mode: no storey containers at the model root'
            else
                parts << "#{storeys.length} storey(s): " + storeys.map { |storey| "#{storey[:name].sub('Storey__', '')} (#{storey[:elements].length} element group(s))" }.join(', ')
            end
            parts << "#{root[:flat].length} flat file group(s)"
            parts << "#{result['export_files'].length} GLB file(s) planned"
            unseen = root[:ignored].values.map(&:length).sum + storeys.map { |storey| storey[:skipped].length }.sum
            parts << "#{unseen} group(s)/component(s) TrueVision will never see" if unseen > 0
            loose_skipped = storeys.map { |storey| storey[:loose].values.sum }.sum
            parts << "#{loose_skipped} loose face(s)/edge(s) directly in storey containers skipped" if loose_skipped > 0
            nested_count = nested.map { |entry| entry['count'] }.sum
            parts << "#{nested_count} nested object(s) on category tags inside exported elements" if nested_count > 0
            parts.join('; ') + '.'
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Objects for Classification
# -----------------------------------------------------------------------------

        def self.na_objects(root, storeys, state)
            objects = []
            storey_containers = storeys.flat_map { |storey| storey[:containers] }
            state[:model].entities.each do |entity|
                next unless Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                next if storey_containers.include?(entity)

                info = na_tag_info(entity.layer, state)
                export = !info[:excluded] && info[:number] && !info[:skip] && info[:stem] ? info[:stem] : nil
                extra = { 'level' => 'root', 'exports_as' => export }
                extra['never_exported'] = na_root_reason(info, true) unless export
                na_add_object(objects, entity, [], extra, 0, state, true)
            end
            storeys.each do |storey|
                storey[:containers].each do |container|
                    container.definition.entities.each do |child|
                        next unless Na__EntityResolver.Na__EntityResolver__IsInstance(child)

                        info = na_tag_info(child.layer, state)
                        reason = na_child_reason(info)
                        extra = { 'level' => 'storey', 'storey' => storey[:name], 'container_id' => container.persistent_id,
                                  'exports_as' => reason ? nil : "#{storey[:name]}__#{info[:element]}" }
                        extra['never_exported'] = reason if reason
                        na_add_object(objects, child, [container], extra, 0, state, true)
                    end
                    loose = na_loose_counts(container.definition.entities)
                    next if loose.empty?

                    objects << { 'type' => 'LooseGeometry', 'level' => 'storey', 'storey' => storey[:name], 'container_id' => container.persistent_id,
                                 'counts' => loose, 'never_exported' => 'loose geometry directly in a storey container' }
                end
            end
            objects
        end

        def self.na_add_object(objects, entity, container_path, extra, depth, state, top_level)
            record = na_object_record(entity, container_path, state, top_level)
            record.merge!(extra.reject { |_key, value| value.nil? })
            objects << record
            return unless depth < state[:options][:expand_depth] && record['container']

            entity.definition.entities.each do |child|
                next unless Na__EntityResolver.Na__EntityResolver__IsInstance(child)

                na_add_object(objects, child, container_path + [entity],
                              { 'level' => 'nested', 'parent_object' => entity.persistent_id, 'storey' => extra['storey'],
                                'exports_as' => extra['exports_as'], 'never_exported' => extra['never_exported'] }, depth + 1, state, false)
            end
        end

        def self.na_object_record(entity, container_path, state, top_level)
            ctx = state[:ctx]
            world = Na__Serializer.Na__Serializer__ToWorld(ctx, container_path)
            definition = entity.definition
            loose = na_loose_counts(definition.entities)
            children = definition.entities.count { |child| Na__EntityResolver.Na__EntityResolver__IsInstance(child) }
            record = { 'id' => entity.persistent_id, 'type' => Na__EntityResolver.Na__EntityResolver__TypeName(entity),
                       'path' => container_path.map(&:persistent_id) }
            name = entity.name.to_s
            record['name'] = name unless name.empty?
            record['definition'] = definition.name if entity.is_a?(Sketchup::ComponentInstance)
            record['copies'] = definition.instances.length if entity.is_a?(Sketchup::ComponentInstance) && definition.instances.length > 1
            info = na_tag_info(entity.layer, state)
            record['tag'] = info[:name] unless info[:untagged]
            record['hidden'] = true if entity.hidden?
            record['tag_hidden'] = true if !info[:untagged] && !entity.layer.visible?
            corners = Na__Serializer.Na__Serializer__TightWorldBounds(entity, ctx, world)
            bounds = Na__Serializer.na_world_bounds_hash(corners, ctx[:unit])
            record['bounds'] = bounds if bounds
            faces = loose.fetch('Face', 0)
            record['faces'] = faces if faces > 0
            record['edges'] = loose['Edge'] if loose.key?('Edge')
            record['children'] = children if children > 0
            label = Na__EntityResolver.Na__EntityResolver__DisplayName(entity)
            record['library_code'] = label[/\A\d{2}_[0-9A-Za-z]{1,6}/] || definition.name[/\A\d{2}_[0-9A-Za-z]{1,6}/] if label =~ NA_LIBRARY_CODE || definition.name =~ NA_LIBRARY_CODE
            record['assembly'] = label[NA_ASSEMBLY_NAME, 1] || definition.name[NA_ASSEMBLY_NAME, 1] if label =~ NA_ASSEMBLY_NAME || definition.name =~ NA_ASSEMBLY_NAME
            dictionaries = ((entity.attribute_dictionaries || []).map(&:name) + (definition.attribute_dictionaries || []).map(&:name)).uniq
            record['dictionaries'] = dictionaries.first(6) unless dictionaries.empty?
            record['container'] = true if children > 0 && faces.zero? && record['library_code'].nil? && record['assembly'].nil?
            if state[:options][:analyse]
                record['analysis'] = na_face_analysis(entity, world[:transform] * entity.transformation, state, top_level)
            end
            record
        end

        def self.na_loose_counts(entities)
            counts = Hash.new(0)
            entities.each do |entity|
                counts['Face'] += 1 if entity.is_a?(Sketchup::Face)
                counts['Edge'] += 1 if entity.is_a?(Sketchup::Edge)
            end
            counts
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Face Analysis (orientation by area, and floor levels)
# -----------------------------------------------------------------------------

        # Area in m2 by orientation over every face inside the object, in world space, plus the
        # heights its upward faces sit at (a stair is a stack of them, one riser apart) and its
        # commonest face materials. Top-level objects also vote for the model's floor levels.
        def self.na_face_analysis(entity, transform, state, vote)
            totals = { 'faces' => 0, 'up_m2' => 0.0, 'down_m2' => 0.0, 'vertical_m2' => 0.0, 'sloped_m2' => 0.0 }
            extra = { levels: Hash.new(0.0), materials: Hash.new(0) }
            na_walk_faces(entity.definition, transform, totals, extra, state, vote, 0)
            totals.each_key { |key| totals[key] = totals[key].round(2) if totals[key].is_a?(Float) }
            levels = extra[:levels].select { |_z, area| area >= NA_LEVEL_MIN_M2 }.keys.sort
            totals['up_levels'] = levels.length
            if levels.length >= 3
                gaps = levels.each_cons(2).map { |low, high| high - low }.sort
                totals['median_rise_mm'] = gaps[gaps.length / 2].round(1)
            end
            totals['materials'] = extra[:materials].sort_by { |_name, count| -count }.first(3).map(&:first) unless extra[:materials].empty?
            totals
        end

        def self.na_walk_faces(definition, transform, totals, extra, state, vote, depth)
            return if depth > 16

            definition.entities.each do |entity|
                if state[:budget] <= 0
                    state[:faces_truncated] = true
                    return
                end
                if entity.is_a?(Sketchup::Face)
                    state[:budget] -= 1
                    totals['faces'] += 1
                    material = entity.material || entity.back_material
                    extra[:materials][material.display_name] += 1 if material
                    area = entity.area(transform) * NA_SQ_IN_TO_SQ_M
                    normal = transform * entity.normal
                    next if normal.length.to_f.zero?

                    normal.normalize!
                    z = normal.z.to_f
                    if z >= NA_HORIZONTAL
                        totals['up_m2'] += area
                        z_mm = (transform * entity.vertices.first.position).z.to_f * 25.4
                        extra[:levels][(z_mm / 10.0).round * 10] += area
                        state[:levels][(z_mm / NA_LEVEL_BIN_MM).round * NA_LEVEL_BIN_MM] += area if vote && area >= NA_LEVEL_MIN_M2
                    elsif z <= -NA_HORIZONTAL
                        totals['down_m2'] += area
                    elsif z.abs <= NA_VERTICAL
                        totals['vertical_m2'] += area
                    else
                        totals['sloped_m2'] += area
                    end
                elsif Na__EntityResolver.Na__EntityResolver__IsInstance(entity)
                    na_walk_faces(entity.definition, transform * entity.transformation, totals, extra, state, vote, depth + 1)
                end
            end
        end

        # The heights with the most upward-facing area: floors, landings, flat roofs, the ground.
        def self.na_levels(state)
            unit = state[:ctx][:unit]
            state[:levels].sort_by { |_z, area| -area }.first(16).map do |z_mm, area|
                { 'z' => Na__Units.Na__Units__FromInches(z_mm / 25.4, unit), 'up_m2' => area.round(2) }
            end.sort_by { |entry| entry['z'] }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Saving
# -----------------------------------------------------------------------------

        def self.na_save(path, overwrite, payload)
            if File.exist?(path) && !overwrite
                raise Na__McpError.new('already_exists', "#{path} already exists.", 'Pass overwrite:true, or another save_path.')
            end

            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, JSON.pretty_generate(payload), encoding: 'UTF-8')
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__TrueVision
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
