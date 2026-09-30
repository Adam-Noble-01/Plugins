# =============================================================================
# NA COMPONENT EDITOR TOOLS - MCP OPERATIONS | LIBRARY CATALOGUE
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__McpOperations__Catalogue__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__McpCatalogue
# PURPOSE    : The read side of the agent library tools: overview, browse,
#              get, next_code, check_name and audit.
# CREATED    : 2026
#
# FAST BY DEFAULT:
# Browsing reads file names only (the same Dir.glob as the Gallery's Scanner),
# plus whatever the Gallery's extract cache already knows (definition name,
# gallery name, category, thumbnail). Only get, and audit with deep: true,
# open files, through Na__LibrarySafeLoad, so the open model never changes.
#
# PATHS:
# Absolute paths use forward slashes exactly as the Scanner builds them, so
# the extract cache ("<path>::<mtime>") is hit. Relative paths in results are
# relative to the library root, e.g. "Na__CoreLib__3dAssets/13__Building__Roof/...".
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__ComponentEditorTools
    module Na__McpCatalogue

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_BROWSE_DEFAULT_LIMIT = 50
        NA_BROWSE_MAX_LIMIT     = 500
        NA_AUDIT_DEEP_LIMIT     = 25
        NA_AUDIT_DEEP_BUDGET_S  = 40

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Library Root, Sets And Paths
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__LibraryRoot
            root = Na__LibraryScanner.Na__ComponentEditorTools__NormalisePath(Na__UserConfig.Na__ComponentEditorTools__LibraryPath).chomp('/')
            if root.empty?
                raise Na__McpOperationsError.new('not_found', 'No component library folder is configured.',
                                                 'Set it in Component Editor Tools > Settings > Library folder.')
            end
            unless Dir.exist?(root)
                raise Na__McpOperationsError.new('not_found', "The library folder does not exist: #{root}", 'Check Settings > Library folder.')
            end

            root
        end

        def self.Na__ComponentEditorTools__BlockedFolders
            Na__UserConfig.Na__ComponentEditorTools__BlockedFolders
        end

        def self.Na__ComponentEditorTools__BlockedFiles
            Na__UserConfig.Na__ComponentEditorTools__BlockedFiles
        end

        # Top folders of the library root, in the Gallery's alias order.
        def self.Na__ComponentEditorTools__Sets(root)
            aliases = Na__UserConfig.Na__ComponentEditorTools__FolderAliases
            blocked = self.Na__ComponentEditorTools__BlockedFolders
            names = Dir.children(root).select { |name| File.directory?(File.join(root, name)) }
            sets = names.map do |name|
                alias_info = aliases[name].is_a?(Hash) ? aliases[name] : {}
                {
                    'name'    => name,
                    'alias'   => alias_info['alias'].to_s,
                    'order'   => alias_info.key?('order') ? alias_info['order'].to_i : 99,
                    'blocked' => blocked.include?(name),
                    'files'   => Dir.glob(File.join(root, name, '**', '*.skp')).length
                }
            end
            sets.sort_by { |set| [set['order'], set['name']] }
        end

        # A set by folder name or Gallery alias; the convention's default when blank.
        def self.Na__ComponentEditorTools__ResolveSet(root, set_text)
            wanted = set_text.to_s.strip
            wanted = Na__McpConvention.Na__ComponentEditorTools__DefaultSet if wanted.empty?
            sets = self.Na__ComponentEditorTools__Sets(root)
            found = sets.find { |set| set['name'].casecmp?(wanted) || (!set['alias'].empty? && set['alias'].casecmp?(wanted)) }
            return found['name'] if found

            raise Na__McpOperationsError.new('not_found', "No library set named '#{wanted}'.",
                                             "Sets: #{sets.map { |set| set['name'] }.join(', ')}.")
        end

        # Absolute path from an absolute path, one relative to the library root
        # ("Na__CoreLib__3dAssets/13__Building__Roof/..."), or one relative to a set
        # ("13__Building__Roof/..."; set_name, else the default set). Must stay inside the root.
        def self.Na__ComponentEditorTools__ResolvePath(root, path_text, set_name = nil)
            text = path_text.to_s.strip.tr('\\', '/')
            raise Na__McpOperationsError.new('invalid_params', 'A path is required.', nil) if text.empty?

            absolute = text =~ %r{\A([A-Za-z]:/|/)}
            candidate = absolute ? text : File.join(root, text)
            unless absolute || Dir.exist?(File.join(root, text.split('/').first.to_s))
                set_folder = set_name.to_s.strip.empty? ? Na__McpConvention.Na__ComponentEditorTools__DefaultSet : set_name.to_s.strip
                candidate = File.join(root, set_folder, text)
            end
            full = File.expand_path(candidate).tr('\\', '/').chomp('/')
            unless full.downcase.start_with?(root.downcase + '/') || full.casecmp?(root)
                raise Na__McpOperationsError.new('invalid_params', "#{path_text} is outside the component library (#{root}).",
                                                 'Pass a path inside the library, or one relative to it.')
            end

            root + full[root.length..]
        end

        def self.Na__ComponentEditorTools__Relative(root, full_path)
            text = full_path.to_s.tr('\\', '/')
            text.downcase.start_with?(root.downcase + '/') ? text[(root.length + 1)..] : text
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scan
# -----------------------------------------------------------------------------

        # Every .skp in a set as an entry hash. Blocked folders (00__Archive,
        # 00__Retired...) are left out unless include_blocked.
        def self.Na__ComponentEditorTools__ScanSet(root, set_name, include_blocked: false)
            blocked_folders = self.Na__ComponentEditorTools__BlockedFolders
            blocked_files = self.Na__ComponentEditorTools__BlockedFiles
            files = Dir.glob(File.join(root, set_name, '**', '*.skp')).sort
            entries = files.map { |path| self.Na__ComponentEditorTools__EntryFor(root, set_name, path, blocked_folders, blocked_files) }
            include_blocked ? entries : entries.reject { |entry| entry['blocked'] }
        end

        def self.Na__ComponentEditorTools__EntryFor(root, set_name, full_path, blocked_folders, blocked_files)
            path = full_path.tr('\\', '/')
            relative = self.Na__ComponentEditorTools__Relative(root, path)
            in_set = relative.sub(%r{\A#{Regexp.escape(set_name)}/}, '')
            folder = File.dirname(in_set)
            folder = '' if folder == '.'
            stem = File.basename(path, '.*')
            parsed = Na__McpConvention.Na__ComponentEditorTools__ParseName(stem)
            context = Na__McpConvention.Na__ComponentEditorTools__FolderContext(folder)
            stat = File.stat(path)
            blocked = folder.split('/').any? { |part| blocked_folders.include?(part) } || blocked_files.include?(File.basename(path))

            {
                'path'            => path,
                'relative_path'   => relative,
                'set'             => set_name,
                'folder'          => folder,
                'file_name'       => File.basename(path),
                'stem'            => stem,
                'code'            => parsed['code'],
                'number'          => parsed['number'],
                'category'        => parsed['category'],
                'kind'            => parsed['kind'],
                'category_folder' => context['category_folder'],
                'series_folder'   => context['series_folder'] || context['bare_series_folder'],
                'size_kb'         => (stat.size / 1024.0).round(1),
                'modified'        => stat.mtime.strftime('%Y-%m-%d %H:%M'),
                'mtime'           => stat.mtime.to_i,
                'blocked'         => blocked
            }
        end

        # What the Gallery's extract cache already knows about this exact file
        # version, or nil. Never opens the file.
        def self.Na__ComponentEditorTools__CachedMeta(entry)
            return nil unless defined?(Na__LibraryExtractor) && Na__LibraryExtractor.respond_to?(:Na__ComponentEditorTools__CachedResult)

            cached = Na__LibraryExtractor.Na__ComponentEditorTools__CachedResult("#{entry['path']}::#{entry['mtime']}")
            return nil unless cached.is_a?(Hash) && cached['ok'] != false

            {
                'definition_name'  => cached['def_name'].to_s,
                'description'      => cached['description'].to_s,
                'gallery_name'     => cached['gallery_name'].to_s,
                'category'         => cached['category'].to_s,
                'type'             => cached['type'].to_s,
                'notes'            => cached['notes'].to_s,
                'truevision_valid' => cached['truevision_valid'].to_s,
                'thumbnail'        => self.Na__ComponentEditorTools__ThumbnailPathFromUri(cached['thumbnail_uri'])
            }
        end

        def self.Na__ComponentEditorTools__ThumbnailPathFromUri(uri_text)
            text = uri_text.to_s
            return '' if text.empty?

            text.sub(%r{\Afile:///}, '').gsub('%20', ' ')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | overview
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Overview(params)
            root = self.Na__ComponentEditorTools__LibraryRoot
            set_name = self.Na__ComponentEditorTools__ResolveSet(root, params['set'])
            all_entries = self.Na__ComponentEditorTools__ScanSet(root, set_name, include_blocked: true)
            visible = all_entries.reject { |entry| entry['blocked'] }
            config = Na__McpConvention.Na__ComponentEditorTools__Config

            categories = self.Na__ComponentEditorTools__CategoryFolders(root, set_name).map do |folder_name|
                self.Na__ComponentEditorTools__CategorySummary(root, set_name, folder_name, visible, all_entries)
            end

            {
                'library_root'    => root,
                'sets'            => self.Na__ComponentEditorTools__Sets(root),
                'set'             => set_name,
                'files'           => visible.length,
                'blocked_folders' => self.Na__ComponentEditorTools__BlockedFolders,
                'categories'      => categories,
                'unfiled'         => visible.select { |entry| entry['category_folder'].nil? }.map { |entry| entry['relative_path'] },
                'convention'      => config['rules'] || {},
                'tags'            => self.Na__ComponentEditorTools__TagMap,
                'taxonomy'        => self.Na__ComponentEditorTools__TaxonomySummary,
                'journals'        => Na__McpLibraryPlan.Na__ComponentEditorTools__RecentJournals(root, 5),
                'summary'         => "#{set_name}: #{visible.length} components in #{categories.length} categories."
            }
        end

        def self.Na__ComponentEditorTools__CategoryFolders(root, set_name)
            base = File.join(root, set_name)
            blocked = self.Na__ComponentEditorTools__BlockedFolders
            Dir.children(base).select { |name| File.directory?(File.join(base, name)) && !blocked.include?(name) }.sort
        end

        def self.Na__ComponentEditorTools__CategorySummary(root, set_name, folder_name, visible, all_entries)
            context = Na__McpConvention.Na__ComponentEditorTools__FolderContext(folder_name)
            base = File.join(root, set_name, folder_name)
            blocked = self.Na__ComponentEditorTools__BlockedFolders
            in_category = visible.select { |entry| entry['folder'] == folder_name || entry['folder'].start_with?("#{folder_name}/") }
            used = self.Na__ComponentEditorTools__UsedNumbers(all_entries, context['category'])

            series = Dir.children(base).select { |name| File.directory?(File.join(base, name)) && !blocked.include?(name) }.sort.map do |series_name|
                series_context = Na__McpConvention.Na__ComponentEditorTools__FolderContext("#{folder_name}/#{series_name}")
                files = in_category.select { |entry| entry['folder'] == "#{folder_name}/#{series_name}" }
                summary = { 'folder' => series_name, 'files' => files.length, 'codes' => self.Na__ComponentEditorTools__CodeSpan(files) }
                if series_context['series_number'] && context['category']
                    range = Na__McpConvention.Na__ComponentEditorTools__SeriesRange(series_context['series_number'])
                    next_number = Na__McpConvention.Na__ComponentEditorTools__NextNumbers(used, range[0], range[1], 1).first
                    summary['next_code'] = next_number ? Na__McpConvention.Na__ComponentEditorTools__FormatCode(context['category'], next_number) : nil
                end
                summary['fix'] = "Rename to #{context['category']}_#{series_name}" if series_context['bare_series_folder'] && context['category']
                summary
            end

            loose = in_category.select { |entry| entry['folder'] == folder_name }
            {
                'folder'      => folder_name,
                'category'    => context['category'],
                'files'       => in_category.length,
                'series'      => series,
                'loose_files' => loose.length,
                'codes'       => self.Na__ComponentEditorTools__CodeSpan(loose),
                'families'    => series.empty? ? self.Na__ComponentEditorTools__Families(loose) : nil
            }.compact
        end

        # Numbers already used in a category, archived and retired files included,
        # so an old code is never handed out again.
        def self.Na__ComponentEditorTools__UsedNumbers(entries, category_number)
            entries.select { |entry| entry['kind'] == 'filed' && entry['category'] == category_number }.map { |entry| entry['number'] }
        end

        def self.Na__ComponentEditorTools__CodeSpan(entries)
            codes = entries.map { |entry| entry['code'] if entry['kind'] == 'filed' }.compact.sort
            codes.empty? ? '' : "#{codes.first}..#{codes.last}"
        end

        # Hundreds families of a flat category: {"0300" => [codes]}.
        def self.Na__ComponentEditorTools__Families(entries)
            families = Hash.new { |hash, key| hash[key] = [] }
            entries.each do |entry|
                next unless entry['kind'] == 'filed'

                families[format('%04d', (entry['number'] / 100) * 100)] << entry['code']
            end
            families.keys.sort.map { |key| { 'family' => key, 'codes' => families[key].sort } }
        end

        def self.Na__ComponentEditorTools__TagMap
            categories = Na__McpConvention.Na__ComponentEditorTools__Config['categories'] || {}
            categories.keys.sort.map do |number|
                info = categories[number]
                { 'category' => number, 'folder' => info['folder'], 'tag' => info['tag'], 'tag_existing' => info['tag_existing'],
                  'tag_proposed' => info['tag_proposed'] }.compact
            end
        end

        def self.Na__ComponentEditorTools__TaxonomySummary
            taxonomy = defined?(Na__Taxonomy) ? Na__Taxonomy.Na__ComponentEditorTools__GetAll : {}
            (taxonomy['categories'] || []).map { |category| { 'category' => category['name'], 'types' => category['types'] || [] } }
        rescue StandardError
            []
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | browse
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Browse(params)
            root = self.Na__ComponentEditorTools__LibraryRoot
            set_name = self.Na__ComponentEditorTools__ResolveSet(root, params['set'])
            entries = self.Na__ComponentEditorTools__ScanSet(root, set_name, include_blocked: params['include_blocked'] == true)
            entries = self.Na__ComponentEditorTools__Filter(entries, params)

            limit = [[(params['limit'] || NA_BROWSE_DEFAULT_LIMIT).to_i, 1].max, NA_BROWSE_MAX_LIMIT].min
            offset = [params['offset'].to_i, 0].max
            page = entries[offset, limit] || []
            items = page.map do |entry|
                meta = self.Na__ComponentEditorTools__CachedMeta(entry) || {}
                check = Na__McpConvention.Na__ComponentEditorTools__CheckAsset(entry['stem'], entry['folder'])
                {
                    'code'             => entry['code'],
                    'file_name'        => entry['file_name'],
                    'folder'           => entry['folder'],
                    'relative_path'    => entry['relative_path'],
                    'kind'             => entry['kind'],
                    'size_kb'          => entry['size_kb'],
                    'modified'         => entry['modified'],
                    'gallery_name'     => meta['gallery_name'],
                    'category'         => meta['category'],
                    'type'             => meta['type'],
                    'truevision_valid' => meta['truevision_valid'] == 'true' ? true : nil,
                    'issues'           => check['issues'].empty? ? nil : check['issues'].map { |issue| issue['rule'] }
                }.reject { |_key, value| value.nil? || value == '' }
            end

            next_offset = offset + page.length < entries.length ? offset + page.length : nil
            {
                'library_root' => root, 'set' => set_name, 'total' => entries.length, 'returned' => items.length,
                'next_offset' => next_offset, 'items' => items,
                'summary' => "#{entries.length} match(es) in #{set_name}, #{items.length} returned."
            }
        end

        def self.Na__ComponentEditorTools__Filter(entries, params)
            folder = params['folder'].to_s.strip.tr('\\', '/').chomp('/')
            category = params['category'].to_s.strip[/\A\d{2}/]
            series = params['series'].to_s.strip
            query = params['query'].to_s.strip.downcase
            kind = params['kind'].to_s.strip

            entries.select do |entry|
                next false unless folder.empty? || entry['folder'] == folder || entry['folder'].start_with?("#{folder}/")
                next false if category && entry['category_folder'].to_s[0, 2] != category
                next false unless series.empty? || entry['series_folder'].to_s.start_with?(series)
                next false unless kind.empty? || entry['kind'] == kind
                next true if query.empty?

                meta = self.Na__ComponentEditorTools__CachedMeta(entry) || {}
                [entry['stem'], meta['gallery_name'], meta['definition_name'], meta['category'], meta['type']].any? do |text|
                    text.to_s.downcase.include?(query)
                end
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | get
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Get(params)
            root = self.Na__ComponentEditorTools__LibraryRoot
            path = self.Na__ComponentEditorTools__ResolvePath(root, params['path'], params['set'])
            unless File.file?(path) && File.extname(path).casecmp?('.skp')
                raise Na__McpOperationsError.new('not_found', "No .skp file at #{path}.", 'Find it with asset_library browse first.')
            end

            set_name = self.Na__ComponentEditorTools__Relative(root, path).split('/').first
            entry = self.Na__ComponentEditorTools__EntryFor(root, set_name, path, self.Na__ComponentEditorTools__BlockedFolders,
                                                           self.Na__ComponentEditorTools__BlockedFiles)
            meta = self.Na__ComponentEditorTools__CachedMeta(entry) || {}
            result = entry.reject { |key, _value| %w[mtime].include?(key) }
            result['cached'] = meta unless meta.empty?

            if params['deep'] == false
                check = Na__McpConvention.Na__ComponentEditorTools__CheckAsset(entry['stem'], entry['folder'], definition_name: meta['definition_name'])
                return result.merge('check' => check)
            end

            thumbnail_path = params['include_thumbnail'] == true ? self.Na__ComponentEditorTools__ThumbnailTarget(path, meta) : nil
            details = Na__LibrarySafeLoad.Na__ComponentEditorTools__WithTemporaryDefinition(path, 'Read library component') do |definition, load_info|
                self.Na__ComponentEditorTools__DefinitionDetails(definition, load_info, thumbnail_path)
            end

            definition_name = details['name_changed_on_load'] ? nil : details['definition_name']
            check = Na__McpConvention.Na__ComponentEditorTools__CheckAsset(entry['stem'], entry['folder'], definition_name: definition_name)
            result.merge!('definition' => details, 'check' => check)
            if thumbnail_path && File.file?(thumbnail_path)
                result['thumbnail'] = { 'image_file' => thumbnail_path, 'mime_type' => 'image/png', 'keep_file' => true }
            end
            result['summary'] = "#{entry['code'] || entry['stem']}: #{details['size_mm'].join(' x ')} mm, " \
                                "#{check['issues'].length} naming issue(s)."
            result
        end

        # Reuse the Gallery's cached thumbnail; otherwise render one into the same cache.
        def self.Na__ComponentEditorTools__ThumbnailTarget(path, meta)
            cached = meta['thumbnail'].to_s
            return cached if !cached.empty? && File.file?(cached)

            directory = Na__PathResolver.Na__ComponentEditorTools__LibraryThumbnailCacheDirectory
            FileUtils.mkdir_p(directory)
            File.join(directory, "#{File.basename(path, '.skp').gsub(/[^A-Za-z0-9_-]/, '_')}.png")
        end

        def self.Na__ComponentEditorTools__DefinitionDetails(definition, load_info, thumbnail_path)
            bounds = definition.bounds
            library = Na__LibrarySerializer.Na__ComponentEditorTools__ReadFromDefinition(definition)
            dictionaries = (definition.attribute_dictionaries || []).map { |dictionary| dictionary.name.to_s }
            if thumbnail_path && !File.file?(thumbnail_path)
                definition.save_thumbnail(thumbnail_path) rescue nil
            end

            {
                'definition_name'      => definition.name.to_s,
                'name_changed_on_load' => load_info[:name_changed_on_load],
                'in_use_in_open_model' => load_info[:in_use],
                'placed_in_open_model' => load_info[:instances],
                'description'          => definition.description.to_s,
                'size_mm'              => [bounds.width, bounds.depth, bounds.height].map { |length| length.to_mm.round(1) },
                'entities'             => definition.entities.length,
                'library_data'         => library,
                'attribute_dictionaries' => dictionaries
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | next_code
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__NextCode(params)
            root = self.Na__ComponentEditorTools__LibraryRoot
            set_name = self.Na__ComponentEditorTools__ResolveSet(root, params['set'])
            entries = self.Na__ComponentEditorTools__ScanSet(root, set_name, include_blocked: true)
            target = self.Na__ComponentEditorTools__TargetFolder(root, set_name, params)
            category = target['category']
            used = self.Na__ComponentEditorTools__UsedNumbers(entries, category)
            count = [[(params['count'] || 1).to_i, 1].max, 20].min

            range = if !params['family'].to_s.strip.empty?
                        Na__McpConvention.Na__ComponentEditorTools__FamilyRange(params['family'])
                    elsif target['series_number']
                        Na__McpConvention.Na__ComponentEditorTools__SeriesRange(target['series_number'])
                    end

            unless range
                return self.Na__ComponentEditorTools__CategoryChoices(root, set_name, target, entries, used)
            end

            numbers = Na__McpConvention.Na__ComponentEditorTools__NextNumbers(used, range[0], range[1], count)
            if numbers.empty?
                raise Na__McpOperationsError.new('operation_failed', "No free code left in #{category}_#{format('%04d', range[0])}..#{format('%04d', range[1])}.",
                                                 'Start a new series folder, or pass another family.')
            end

            codes = numbers.map { |number| Na__McpConvention.Na__ComponentEditorTools__FormatCode(category, number) }
            neighbours = entries.select { |entry| entry['kind'] == 'filed' && entry['category'] == category && entry['number'].between?(range[0], range[1]) }
                                .sort_by { |entry| entry['number'] }.last(6).map { |entry| entry['relative_path'] }
            taxonomy = Na__McpConvention.Na__ComponentEditorTools__TaxonomyFor(category, target['series_code'])
            {
                'set'           => set_name,
                'category'      => category,
                'folder'        => target['folder'],
                'range'         => [Na__McpConvention.Na__ComponentEditorTools__FormatCode(category, range[0]),
                                    Na__McpConvention.Na__ComponentEditorTools__FormatCode(category, range[1])],
                'code'          => codes.first,
                'codes'         => codes,
                'neighbours'    => neighbours,
                'template'      => "#{codes.first}__<Series>__<Item>__<Descriptor>__Type-01__<Size>__.skp",
                'taxonomy'      => { 'category' => taxonomy[0], 'type' => taxonomy[1] },
                'summary'       => "Next free code in #{target['folder']}: #{codes.join(', ')}."
            }
        end

        # Resolves folder / series / category params into the folder the new file
        # goes in: {folder, category, series_code, series_number}.
        def self.Na__ComponentEditorTools__TargetFolder(root, set_name, params)
            folder = params['folder'].to_s.strip.tr('\\', '/').chomp('/')
            series = params['series'].to_s.strip
            category = params['category'].to_s.strip

            if folder.empty? && !series.empty?
                folder = self.Na__ComponentEditorTools__FindSeriesFolder(root, set_name, series)
            end
            if folder.empty? && !category.empty?
                folder = self.Na__ComponentEditorTools__FindCategoryFolder(root, set_name, category)
            end
            if folder.empty?
                raise Na__McpOperationsError.new('invalid_params', 'Say where the component goes.',
                                                 'Pass folder ("13__Building__Roof/13_5000__RidgeCrestings"), series ("13_5000") or category ("13").')
            end

            context = Na__McpConvention.Na__ComponentEditorTools__FolderContext(folder)
            unless context['category']
                raise Na__McpOperationsError.new('invalid_params', "#{folder} does not start with an NN__Category folder.",
                                                 'Use asset_library overview to see the category folders.')
            end

            { 'folder' => folder, 'category' => context['category'], 'series_code' => context['series_code'],
              'series_number' => context['series_number'] }
        end

        def self.Na__ComponentEditorTools__FindCategoryFolder(root, set_name, category_text)
            number = category_text[/\A\d{2}/]
            match = self.Na__ComponentEditorTools__CategoryFolders(root, set_name).find do |name|
                number ? name.start_with?("#{number}__") : name.casecmp?(category_text)
            end
            return match if match

            raise Na__McpOperationsError.new('not_found', "No category folder #{category_text} in #{set_name}.",
                                             'Create it first with asset_library_edit create_folder, e.g. "12__Building__Floors".')
        end

        def self.Na__ComponentEditorTools__FindSeriesFolder(root, set_name, series_text)
            self.Na__ComponentEditorTools__CategoryFolders(root, set_name).each do |category_name|
                base = File.join(root, set_name, category_name)
                Dir.children(base).sort.each do |name|
                    next unless File.directory?(File.join(base, name))
                    return "#{category_name}/#{name}" if name.start_with?(series_text) || name.casecmp?(series_text)
                end
            end
            raise Na__McpOperationsError.new('not_found', "No series folder #{series_text} in #{set_name}.",
                                             'Pass the category instead to see its series, or create the series folder first.')
        end

        # No series or family given: list the choices in the category.
        def self.Na__ComponentEditorTools__CategoryChoices(root, set_name, target, entries, used)
            summary = self.Na__ComponentEditorTools__CategorySummary(root, set_name, target['folder'].split('/').first,
                                                                      entries.reject { |entry| entry['blocked'] }, entries)
            highest = used.max
            flat_next = highest ? Na__McpConvention.Na__ComponentEditorTools__NextNumbers(used, 1, 9999, 1).first : 1
            {
                'set'        => set_name,
                'category'   => target['category'],
                'folder'     => target['folder'],
                'code'       => nil,
                'series'     => summary['series'],
                'families'   => summary['families'],
                'next_after_highest' => flat_next ? Na__McpConvention.Na__ComponentEditorTools__FormatCode(target['category'], flat_next) : nil,
                'summary'    => 'Pick a series (series) or a hundreds family (family, e.g. "60_03"): codes are allocated inside it.'
            }.compact
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | check_name
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__CheckName(params)
            root = self.Na__ComponentEditorTools__LibraryRoot
            set_name = self.Na__ComponentEditorTools__ResolveSet(root, params['set'])
            name = params['name'].to_s.strip
            if name.empty?
                raise Na__McpOperationsError.new('invalid_params', 'Pass name (the file name or definition name to check).', nil)
            end

            folder = params['folder'].to_s.strip.tr('\\', '/').chomp('/')
            check = Na__McpConvention.Na__ComponentEditorTools__CheckAsset(File.basename(name.tr('\\', '/')), folder)
            if check['code']
                owners = self.Na__ComponentEditorTools__ScanSet(root, set_name, include_blocked: true)
                             .select { |entry| entry['code'] == check['code'] && entry['stem'] != check['name'] }
                unless owners.empty?
                    check['issues'] << Na__McpConvention.Na__ComponentEditorTools__Issue(
                        'error', 'code_taken', "#{check['code']} is already used by #{owners.map { |entry| entry['relative_path'] }.join(', ')}.",
                        'Take the next free code with next_code.'
                    )
                end
            end

            errors = check['issues'].count { |issue| issue['level'] == 'error' }
            check.merge('ok' => errors.zero?, 'summary' => errors.zero? ? 'The name follows the convention.' : "#{errors} error(s) in the name.")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | audit
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Audit(params)
            root = self.Na__ComponentEditorTools__LibraryRoot
            set_name = self.Na__ComponentEditorTools__ResolveSet(root, params['set'])
            all_entries = self.Na__ComponentEditorTools__ScanSet(root, set_name, include_blocked: true)
            entries = all_entries.reject { |entry| entry['blocked'] && params['include_blocked'] != true }
            entries = self.Na__ComponentEditorTools__Filter(entries, params.merge('query' => ''))

            duplicates = entries.select { |entry| entry['kind'] == 'filed' && !entry['blocked'] }.group_by { |entry| entry['code'] }
                                .select { |_code, owners| owners.length > 1 }
            deep_names = params['deep'] == true ? self.Na__ComponentEditorTools__DeepDefinitionNames(entries, params) : {}

            items = entries.map do |entry|
                cached_name = (self.Na__ComponentEditorTools__CachedMeta(entry) || {})['definition_name']
                definition_name = deep_names[entry['path']]
                unreadable = definition_name.to_s.start_with?('(')
                check = Na__McpConvention.Na__ComponentEditorTools__CheckAsset(entry['stem'], entry['folder'],
                                                                              definition_name: unreadable ? nil : definition_name)
                if unreadable
                    check['issues'] << Na__McpConvention.Na__ComponentEditorTools__Issue('error', 'unreadable', definition_name, nil)
                end
                if duplicates.key?(entry['code'])
                    others = duplicates[entry['code']].reject { |other| other['path'] == entry['path'] }.map { |other| other['file_name'] }
                    check['issues'] << Na__McpConvention.Na__ComponentEditorTools__Issue('error', 'duplicate_code',
                                                                                         "#{entry['code']} is also used by #{others.join(', ')}.",
                                                                                         'Give all but one a new code (next_code).')
                end
                next nil if check['issues'].empty?

                {
                    'relative_path'   => entry['relative_path'],
                    'code'            => entry['code'],
                    'kind'            => entry['kind'],
                    'definition_name' => definition_name || (cached_name.to_s.empty? ? nil : cached_name),
                    'issues'          => check['issues'],
                    'suggested_name'  => check['suggested_name']
                }.compact
            end.compact

            rules = Hash.new(0)
            items.each { |item| item['issues'].each { |issue| rules[issue['rule']] += 1 } }
            limit = [[(params['limit'] || 100).to_i, 1].max, NA_BROWSE_MAX_LIMIT].min
            offset = [params['offset'].to_i, 0].max
            page = items[offset, limit] || []
            {
                'set' => set_name, 'checked' => entries.length, 'with_issues' => items.length, 'by_rule' => rules,
                'duplicate_codes' => duplicates.transform_values { |owners| owners.map { |entry| entry['relative_path'] } },
                'deep_checked' => deep_names.length, 'items' => page,
                'next_offset' => offset + page.length < items.length ? offset + page.length : nil,
                'summary' => "#{items.length} of #{entries.length} components in #{set_name} break the convention" \
                             "#{deep_names.empty? ? '' : " (#{deep_names.length} opened to check the name inside)"}."
            }
        end

        # Opens up to limit files (deep: true) to read the definition name inside.
        # A name SketchUp suffixed on load is reported as unknown (nil).
        def self.Na__ComponentEditorTools__DeepDefinitionNames(entries, params)
            started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            limit = [[(params['deep_limit'] || NA_AUDIT_DEEP_LIMIT).to_i, 1].max, 200].min
            names = {}
            entries.first(limit).each do |entry|
                break if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > NA_AUDIT_DEEP_BUDGET_S

                names[entry['path']] = Na__LibrarySafeLoad.Na__ComponentEditorTools__WithTemporaryDefinition(entry['path'], 'Audit library component') do |definition, load_info|
                    load_info[:name_changed_on_load] ? nil : definition.name.to_s
                end
            rescue StandardError => error
                names[entry['path']] = "(could not open: #{error.message})"
            end
            names
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
