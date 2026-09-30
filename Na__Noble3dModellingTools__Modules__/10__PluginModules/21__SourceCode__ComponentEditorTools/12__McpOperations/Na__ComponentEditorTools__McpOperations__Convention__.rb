# =============================================================================
# NA COMPONENT EDITOR TOOLS - MCP OPERATIONS | LIBRARY NAMING CONVENTION
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__McpOperations__Convention__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__McpConvention
# PURPOSE    : Read, check and build library names and codes the way Adam
#              files components, so an agent names and numbers new assets
#              exactly like its neighbours.
# CREATED    : 2026
#
# @delegate: ../07__UserData/Na__ComponentEditorTools__LibraryConvention__.json
#
# THE CONVENTION (read from Adam's Na and Va libraries, 30-Sep-2026):
#   <set>/NN__Domain__Category/NN_S000__Series/NN_NNNN__Series__Item__Descriptor__Type-01__Size__.skp
# - NN is the category folder number. It mirrors the SSOT tag numbers
#   (11-19 building elements, 08/09 site, 60 entourage).
# - A series folder NN_S000__Name owns the codes in its thousand; a finer base
#   such as 10_2010 owns its ten. Codes ending in 0 are kept for folder bases.
# - A category with no series folders numbers in hundreds families
#   (60_03xx people, 60_05xx animals).
# - Segments are joined by __, words are PascalCase, a hyphen joins words in a
#   segment (Type-01, 14m-Height), and every name ends with __ before .skp.
# - The component definition inside a file is named exactly like the file.
#
# Pure Ruby: no SketchUp API here, so the rules can be tested outside SketchUp.
#
# =============================================================================

require 'json'

module Na__ComponentEditorTools
    module Na__McpConvention

# -----------------------------------------------------------------------------
# REGION | Name And Folder Patterns
# -----------------------------------------------------------------------------

        NA_CODE_NAME       = /\A(\d{2})_(\d{4})__(.*)\z/m.freeze
        NA_PLACEHOLDER     = /\A(\d{2})_N{4}__(.*)\z/m.freeze
        NA_SHORT_CODE      = /\A(\d{2})_(\d{1,3})__(.*)\z/m.freeze
        NA_LETTER_CODE     = /\A([A-Z]{2,5})(\d{2,5})__(.*)\z/m.freeze
        NA_OLD_PREFIX      = /\A(\d{2})_([A-Za-z].*)\z/m.freeze
        NA_PREFIX_ONLY     = /\A(\d{2})__(.*)\z/m.freeze
        NA_CATEGORY_FOLDER = /\A(\d{2})__(\S+)\z/.freeze
        NA_SERIES_FOLDER   = /\A(\d{2})_(\d{4})__(\S+)\z/.freeze
        NA_BARE_SERIES     = /\A(\d{4})__(\S+)\z/.freeze
        NA_MANGLED_SUFFIX  = /#\d+/.freeze
        NA_CONTROL_CHARS   = /[\r\n\t]/.freeze
        NA_DEFAULT_SEGMENT = /\A[A-Za-z0-9.&()+-]+(?:_[A-Za-z0-9.&()+-]+)*\z/.freeze
        NA_CONFIG_FILE     = 'Na__ComponentEditorTools__LibraryConvention__.json'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Convention Config
# -----------------------------------------------------------------------------

        # The JSON rules, re-read whenever the file changes on disk.
        def self.Na__ComponentEditorTools__Config
            path = self.Na__ComponentEditorTools__ConfigPath
            stamp = File.file?(path) ? File.mtime(path).to_i : 0
            return @na_config if @na_config && @na_config_stamp == stamp

            parsed = stamp.zero? ? {} : JSON.parse(File.read(path, encoding: 'UTF-8'))
            @na_config_stamp = stamp
            @na_config = parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError => error
            raise Na__McpOperationsError.new('file_error', "The library convention file is not valid JSON: #{error.message}",
                                             "Fix #{NA_CONFIG_FILE} in 07__UserData.")
        end

        def self.Na__ComponentEditorTools__ConfigPath
            @na_config_path_override || File.join(Na__PathResolver.Na__ComponentEditorTools__UserDataDirectory, NA_CONFIG_FILE)
        end

        # Tests point the convention at their own JSON.
        def self.Na__ComponentEditorTools__UseConfigPath(path_text)
            @na_config_path_override = path_text
            @na_config = nil
        end

        def self.Na__ComponentEditorTools__DefaultSet
            self.Na__ComponentEditorTools__Config['default_set'].to_s
        end

        def self.Na__ComponentEditorTools__UnfiledPrefixes
            Array(self.Na__ComponentEditorTools__Config['unfiled_prefixes']).map(&:to_s)
        end

        def self.Na__ComponentEditorTools__SegmentPattern
            text = self.Na__ComponentEditorTools__Config['allowed_segment_pattern'].to_s
            text.empty? ? NA_DEFAULT_SEGMENT : Regexp.new(text)
        rescue RegexpError
            NA_DEFAULT_SEGMENT
        end

        def self.Na__ComponentEditorTools__CategoryInfo(category_number)
            categories = self.Na__ComponentEditorTools__Config['categories']
            info = categories.is_a?(Hash) ? categories[category_number.to_s] : nil
            info.is_a?(Hash) ? info : {}
        end

        # [category, type] for the gallery filters: the series default, else the category's.
        def self.Na__ComponentEditorTools__TaxonomyFor(category_number, series_code = nil)
            series_map = self.Na__ComponentEditorTools__Config['series_taxonomy']
            pair = series_map.is_a?(Hash) && series_code ? series_map[series_code.to_s] : nil
            pair ||= self.Na__ComponentEditorTools__CategoryInfo(category_number)['taxonomy']
            pair.is_a?(Array) ? [pair[0].to_s, pair[1].to_s] : ['', '']
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Parse A Name
# -----------------------------------------------------------------------------

        # Splits a file stem or definition name into code and segments.
        # kind: filed (NN_NNNN), placeholder (NN_NNNN in letters), short_code (27_22),
        # letter_code (ADR6001), old_prefix (04_Whitecard), unfiled (85__, TEMP__...),
        # prefix_only (NN__ with no number), uncoded.
        def self.Na__ComponentEditorTools__ParseName(name_text)
            stem = self.Na__ComponentEditorTools__StripSkp(name_text)
            parsed = {
                'name' => stem, 'kind' => 'uncoded', 'code' => nil, 'category' => nil, 'number' => nil,
                'segments' => [], 'trailing_underscores' => stem.end_with?('__') && !stem.end_with?('___')
            }
            rest = stem

            if (match = NA_CODE_NAME.match(stem))
                parsed.merge!('kind' => 'filed', 'category' => match[1], 'number' => match[2].to_i, 'code' => "#{match[1]}_#{match[2]}")
                rest = match[3]
            elsif (match = NA_PLACEHOLDER.match(stem))
                parsed.merge!('kind' => 'placeholder', 'category' => match[1])
                rest = match[2]
            elsif self.Na__ComponentEditorTools__UnfiledPrefix(stem)
                parsed['kind'] = 'unfiled'
                rest = stem.sub(self.Na__ComponentEditorTools__UnfiledPrefix(stem), '')
            elsif (match = NA_SHORT_CODE.match(stem))
                parsed.merge!('kind' => 'short_code', 'category' => match[1], 'code' => "#{match[1]}_#{match[2]}")
                rest = match[3]
            elsif (match = NA_LETTER_CODE.match(stem))
                parsed.merge!('kind' => 'letter_code', 'code' => "#{match[1]}#{match[2]}")
                rest = match[3]
            elsif (match = NA_PREFIX_ONLY.match(stem))
                parsed.merge!('kind' => 'prefix_only', 'category' => match[1])
                rest = match[2]
            elsif (match = NA_OLD_PREFIX.match(stem))
                parsed.merge!('kind' => 'old_prefix', 'category' => match[1])
                rest = match[2]
            end

            parsed['segments'] = rest.sub(/_+\z/, '').split('__', -1)
            parsed
        end

        # "Name__.skp" -> "Name__" (any case of the extension); other text unchanged.
        def self.Na__ComponentEditorTools__StripSkp(name_text)
            text = name_text.to_s
            File.extname(text).casecmp?('.skp') ? text[0...-4] : text
        end

        def self.Na__ComponentEditorTools__UnfiledPrefix(stem)
            self.Na__ComponentEditorTools__UnfiledPrefixes.find { |prefix| stem.to_s.start_with?(prefix) }
        end

        # "13_2001" from category "13" and number 2001.
        def self.Na__ComponentEditorTools__FormatCode(category_number, number)
            format('%02d_%04d', category_number.to_i, number.to_i)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Folder Context
# -----------------------------------------------------------------------------

        # What the folders above a file say about its code. folder_in_set is the
        # path inside the library set, e.g. "13__Building__Roof/13_2000__ChimneyPots".
        def self.Na__ComponentEditorTools__FolderContext(folder_in_set)
            parts = folder_in_set.to_s.tr('\\', '/').split('/').reject { |part| part.empty? || part == '.' }
            context = {
                'parts' => parts, 'category_folder' => nil, 'category' => nil, 'series_folder' => nil,
                'series_code' => nil, 'series_number' => nil, 'series_category' => nil, 'bare_series_folder' => nil
            }

            first = parts[0]
            if first && (match = NA_CATEGORY_FOLDER.match(first))
                context['category_folder'] = first
                context['category'] = match[1]
            end

            second = parts[1]
            if second && (match = NA_SERIES_FOLDER.match(second))
                context.merge!('series_folder' => second, 'series_code' => "#{match[1]}_#{match[2]}",
                               'series_number' => match[2].to_i, 'series_category' => match[1])
            elsif second && (match = NA_BARE_SERIES.match(second))
                context.merge!('bare_series_folder' => second, 'series_number' => match[1].to_i)
            end
            context
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Checks
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Issue(level, rule, message_text, fix_text = nil)
            issue = { 'level' => level, 'rule' => rule, 'message' => message_text }
            issue['fix'] = fix_text if fix_text
            issue
        end

        # Problems with the name itself, wherever the file sits.
        def self.Na__ComponentEditorTools__NameIssues(parsed)
            issues = []
            stem = parsed['name'].to_s

            case parsed['kind']
            when 'placeholder'
                issues << self.Na__ComponentEditorTools__Issue('warning', 'number_not_allocated', 'The number is still NNNN.',
                                                               'Allocate one with asset_library next_code, then rename.')
            when 'short_code'
                issues << self.Na__ComponentEditorTools__Issue('error', 'short_code', "The code #{parsed['code']} is not NN_NNNN.",
                                                               'Give it a four-digit number in its series (next_code), then rename.')
            when 'letter_code'
                issues << self.Na__ComponentEditorTools__Issue('error', 'letter_code', "#{parsed['code']} is a letter code from another scheme.",
                                                               'Give it the NN_NNNN code of its folder (next_code), then rename.')
            when 'old_prefix'
                issues << self.Na__ComponentEditorTools__Issue('error', 'old_prefix', "The #{parsed['category']}_ prefix is from an older numbering.",
                                                               'Give it the NN_NNNN code of its folder (next_code), then rename.')
            when 'prefix_only'
                issues << self.Na__ComponentEditorTools__Issue('error', 'no_number', "#{parsed['category']}__ has no four-digit number.",
                                                               'Give it the NN_NNNN code of its folder (next_code), then rename.')
            when 'unfiled'
                issues << self.Na__ComponentEditorTools__Issue('warning', 'unfiled', "Unfiled (#{self.Na__ComponentEditorTools__UnfiledPrefix(stem)}).",
                                                               'File it with a code in its category when it is ready.')
            when 'uncoded'
                issues << self.Na__ComponentEditorTools__Issue('error', 'no_code', 'The name has no NN_NNNN code.',
                                                               'Give it the next free code in its folder (next_code), then rename.')
            end

            if stem =~ NA_CONTROL_CHARS
                issues << self.Na__ComponentEditorTools__Issue('error', 'control_characters', 'The name contains a line break or tab.', 'Retype the name.')
            end
            issues << self.Na__ComponentEditorTools__Issue('error', 'spaces', 'The name contains spaces.', 'Use PascalCase words joined by __.') if stem.include?(' ')
            if stem =~ NA_MANGLED_SUFFIX
                issues << self.Na__ComponentEditorTools__Issue('error', 'mangled_name', "#{stem[NA_MANGLED_SUFFIX]} is SketchUp's duplicate-name suffix.",
                                                               'Rename it to the name it should have.')
            end
            if %w[filed placeholder].include?(parsed['kind']) && !parsed['trailing_underscores']
                issues << self.Na__ComponentEditorTools__Issue('warning', 'trailing_underscores', 'The name should end with __.', 'Add __ before .skp.')
            end
            if stem.include?('___')
                issues << self.Na__ComponentEditorTools__Issue('warning', 'extra_underscores', 'The name has three or more underscores in a row.',
                                                               'Use exactly __ between segments.')
            end

            pattern = self.Na__ComponentEditorTools__SegmentPattern
            parsed['segments'].each do |segment|
                next if segment.empty? || segment =~ pattern

                issues << self.Na__ComponentEditorTools__Issue('warning', 'segment_characters',
                                                               "Segment '#{segment}' has characters outside A-Z a-z 0-9 . - & ( ) +.",
                                                               'Remove them or replace them with a hyphen.')
            end

            (self.Na__ComponentEditorTools__Config['word_fixes'] || {}).each do |wrong, right|
                next unless stem.include?(wrong.to_s)

                issues << self.Na__ComponentEditorTools__Issue('warning', 'typo', "'#{wrong}' looks like a typo of '#{right}'.", "Use #{right}.")
            end
            issues
        end

        # Problems with where the file sits compared with its code.
        def self.Na__ComponentEditorTools__FolderIssues(parsed, context)
            issues = []
            if context['parts'].empty?
                issues << self.Na__ComponentEditorTools__Issue('warning', 'set_root', 'The file sits in the root of the library set.',
                                                               'Move it into its category folder.')
                return issues
            end

            unless context['category_folder']
                issues << self.Na__ComponentEditorTools__Issue('warning', 'category_folder_name', "#{context['parts'][0]} is not an NN__Category folder.", nil)
            end
            if context['bare_series_folder'] && context['category']
                wanted = "#{context['category']}_#{context['bare_series_folder']}"
                issues << self.Na__ComponentEditorTools__Issue('warning', 'series_folder_name',
                                                               "The series folder #{context['bare_series_folder']} has no category prefix.",
                                                               "Rename the folder to #{wanted}.")
            end
            if context['series_category'] && context['category'] && context['series_category'] != context['category']
                issues << self.Na__ComponentEditorTools__Issue('warning', 'series_folder_name',
                                                               "#{context['series_folder']} sits in category #{context['category']}.", nil)
            end

            return issues unless parsed['kind'] == 'filed' && context['category']

            if parsed['category'] != context['category']
                wanted = self.Na__ComponentEditorTools__FormatCode(context['category'], parsed['number'])
                issues << self.Na__ComponentEditorTools__Issue('error', 'category_mismatch',
                                                               "Code #{parsed['code']} sits in category folder #{context['category_folder']}.",
                                                               "Use #{wanted} if it is free (next_code checks), or move the file.")
            elsif context['series_number'] && (parsed['number'] / 1000) != (context['series_number'] / 1000)
                issues << self.Na__ComponentEditorTools__Issue('warning', 'series_mismatch',
                                                               "Code #{parsed['code']} is outside the #{context['series_folder'] || context['bare_series_folder']} series.",
                                                               'Give it a code in the series (next_code), or move it to its own series.')
            end
            issues
        end

        # Every issue for one asset: its name, its folder and (when known) the
        # definition name inside the file.
        def self.Na__ComponentEditorTools__CheckAsset(stem, folder_in_set, definition_name: nil)
            parsed = self.Na__ComponentEditorTools__ParseName(stem)
            context = self.Na__ComponentEditorTools__FolderContext(folder_in_set)
            issues = self.Na__ComponentEditorTools__NameIssues(parsed) + self.Na__ComponentEditorTools__FolderIssues(parsed, context)

            if definition_name && definition_name.to_s != parsed['name']
                issues << self.Na__ComponentEditorTools__Issue('error', 'definition_name',
                                                               "The component inside is named '#{definition_name}', not like the file.",
                                                               'Rename or update it with def_name "auto" so the two match.')
            end

            parsed.merge('folder' => context, 'issues' => issues, 'suggested_name' => self.Na__ComponentEditorTools__SuggestFix(parsed, context, issues))
        end

        # A mechanical fix for the rules that have one (trailing __, runs of
        # underscores, known typos, a code prefix that disagrees with its folder).
        # nil when nothing can be fixed mechanically, including every name without
        # an NN_NNNN code: that needs a code allocated (next_code), not a tidy.
        def self.Na__ComponentEditorTools__SuggestFix(parsed, context, issues)
            return nil unless %w[filed placeholder].include?(parsed['kind'])

            rules = issues.map { |issue| issue['rule'] }
            stem = parsed['name'].to_s.gsub(NA_CONTROL_CHARS, '').strip
            stem = stem.gsub(/_{3,}/, '__')
            (self.Na__ComponentEditorTools__Config['word_fixes'] || {}).each { |wrong, right| stem = stem.gsub(wrong.to_s, right.to_s) }
            if rules.include?('category_mismatch') && context['category']
                stem = stem.sub(/\A\d{2}_/, "#{context['category']}_")
            end
            stem += '__' if %w[filed placeholder].include?(parsed['kind']) && !stem.end_with?('__')
            stem == parsed['name'] ? nil : stem
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Build Names
# -----------------------------------------------------------------------------

        # "13_5001" + "Roof__RidgeFinial__FleurDeLis__Type-01" -> "13_5001__Roof__RidgeFinial__FleurDeLis__Type-01__".
        # name_text may already carry a code, the trailing __ or .skp: they are dropped.
        def self.Na__ComponentEditorTools__BuildStem(code_text, name_text)
            code = code_text.to_s.strip
            unless code =~ /\A\d{2}_\d{4}\z/
                raise Na__McpOperationsError.new('invalid_params', "The code '#{code}' is not NN_NNNN.", 'Pass code like 13_5002, or omit it to take the next free one.')
            end

            body = self.Na__ComponentEditorTools__StripSkp(name_text.to_s.strip).sub(/\A\d{2}_\d{4}__/, '')
            segments = body.split('__').map(&:strip).reject(&:empty?)
            if segments.empty?
                raise Na__McpOperationsError.new('invalid_params', 'The name has no segments after the code.',
                                                 'Pass name like "Roof__RidgeFinial__FleurDeLis__Type-01".')
            end

            "#{code}__#{segments.join('__')}__"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Code Ranges And Allocation
# -----------------------------------------------------------------------------

        # The block a series base owns: 2000 -> 2000..2999, 2200 -> 2200..2299,
        # 2010 -> 2010..2019. A base with no trailing zero owns its thousand.
        def self.Na__ComponentEditorTools__SeriesRange(base_number)
            base = base_number.to_i
            zeros = 0
            probe = base
            while probe.positive? && (probe % 10).zero? && zeros < 3
                probe /= 10
                zeros += 1
            end
            return [(base / 1000) * 1000, (base / 1000) * 1000 + 999] if zeros.zero?

            [base, base + (10**zeros) - 1]
        end

        # A family prefix: "13_20" -> 2000..2099, "202" -> 2020..2029, "60_03" -> 300..399.
        def self.Na__ComponentEditorTools__FamilyRange(family_text)
            digits = family_text.to_s.strip.sub(/\A\d{2}_/, '')
            unless digits =~ /\A\d{1,3}\z/
                raise Na__McpOperationsError.new('invalid_params', "family '#{family_text}' is not 1 to 3 digits after the category.",
                                                 'Pass family like "13_20" (2000-2099) or "60_03" (0300-0399).')
            end

            size = 10**(4 - digits.length)
            start = digits.to_i * size
            [start, start + size - 1]
        end

        # The next free numbers in range_start..range_end after the highest used
        # one, skipping numbers that end in 0 (kept for folder bases).
        def self.Na__ComponentEditorTools__NextNumbers(used_numbers, range_start, range_end, count = 1)
            used = used_numbers.map(&:to_i)
            in_range = used.select { |number| number >= range_start && number <= range_end }
            candidate = in_range.empty? ? range_start : in_range.max
            found = []
            while found.length < count
                candidate += 1
                break if candidate > range_end
                next if (candidate % 10).zero? || used.include?(candidate)

                found << candidate
            end
            found
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
