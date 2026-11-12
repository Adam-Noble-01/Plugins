# =============================================================================
# NA AGENT OUTLINER - APP DATA - CONFIG STORE
# =============================================================================
#
# FILE       : Na__AgentOutliner__AppData__ConfigStore__.rb
# NAMESPACE  : Na__AgentOutliner::Na__ConfigStore
# MODULE     : Na__ConfigStore (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Read and write the three files this tool keeps outside the
#              model: the app defaults, Adam's own settings on this PC, and
#              the shared naming standards (prefixes and flag types)
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - CONFIG FIRST: every tunable lives in ...AppConfig__Defaults__.json. The
#   Settings tab writes only Adam's differences into the user config, which is
#   deep merged over the defaults, so a new default reaches him at once.
# - THE STANDARDS FILE is committed and shared between Adam's PCs. A save
#   validates first, keeps a .bak of the previous file, and writes through a
#   temporary file so a crash mid write never leaves half a file.
# - AN UNREADABLE FILE is renamed .corrupt-<time>.json and the defaults are
#   used, never a silent empty list (an empty Quick Name bar would read as
#   "no standards" when the file is only broken).
# - TYPES: a setting saved from the dialog is coerced to the type of its
#   default (true/false, number, text, list of numbers); unknown keys are
#   dropped, so a stale page can never write junk into the file.
#
# =============================================================================

module Na__AgentOutliner
    module Na__ConfigStore

# -----------------------------------------------------------------------------
# REGION | Constants and State
# -----------------------------------------------------------------------------

        NA_APPCONFIG_FILE  = 'Na__AgentOutliner__AppData__AppConfig__Defaults__.json'.freeze     unless defined?(NA_APPCONFIG_FILE)
        NA_STANDARDS_FILE  = 'Na__AgentOutliner__AppData__NamingStandards__.json'.freeze         unless defined?(NA_STANDARDS_FILE)
        NA_USERCONFIG_FILE = 'Na__AgentOutliner__UserConfig__.json'.freeze                       unless defined?(NA_USERCONFIG_FILE)

        NA_LABEL_PATTERN   = /\A[A-Za-z0-9][A-Za-z0-9\-]*(?:__[A-Za-z0-9][A-Za-z0-9\-]*)*\z/.freeze unless defined?(NA_LABEL_PATTERN)
        NA_FLAG_ID_PATTERN = /\A[a-z][a-z0-9_]{0,39}\z/.freeze                                   unless defined?(NA_FLAG_ID_PATTERN)
        NA_COLOUR_PATTERN  = /\A#[0-9a-fA-F]{6}\z/.freeze                                        unless defined?(NA_COLOUR_PATTERN)
        NA_MODES           = %w[replace prefix].freeze                                           unless defined?(NA_MODES)

        @na_app_config = nil unless defined?(@na_app_config)
        @na_user       = nil unless defined?(@na_user)
        @na_standards  = nil unless defined?(@na_standards)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Paths
# -----------------------------------------------------------------------------

        def self.Na__Config__AppConfigPath
            File.join(Na__AgentOutliner::NA_APPDATA_ROOT, NA_APPCONFIG_FILE)
        end

        def self.Na__Config__StandardsPath
            File.join(Na__AgentOutliner::NA_APPDATA_ROOT, NA_STANDARDS_FILE)
        end

        def self.Na__Config__UserConfigPath
            File.join(Na__AgentOutliner::NA_LOCAL_ROOT, NA_USERCONFIG_FILE)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | App Defaults and Settings
# -----------------------------------------------------------------------------

        # FUNCTION | The App Defaults (cached until Reload Plugin Data)
        # ------------------------------------------------------------
        def self.Na__Config__App
            @na_app_config ||= self.na_read_json(self.Na__Config__AppConfigPath) || {}
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Value From the App Defaults, or the Fallback Given
        # ------------------------------------------------------------
        def self.Na__Config__GetOr(fallback, *keys)
            value = keys.reduce(self.Na__Config__App) { |node, key| node.is_a?(Hash) ? node[key.to_s] : nil }
            value.nil? ? fallback : value
        end
        # ---------------------------------------------------------------

        # FUNCTION | An Engine Tunable (not shown in the dialog)
        # ------------------------------------------------------------
        def self.Na__Config__Engine(key, fallback = nil)
            self.Na__Config__GetOr(fallback, 'engine', key)
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Settings Adam Sees: Defaults With His Own Choices Over Them
        # ------------------------------------------------------------
        def self.Na__Config__Settings
            defaults = self.Na__Config__GetOr({}, 'settings')
            mine     = self.Na__UserConfig__All['settings']
            self.na_deep_merge(defaults, mine.is_a?(Hash) ? mine : {})
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Setting (group, key)
        # ------------------------------------------------------------
        def self.Na__Config__Setting(group, key)
            settings = self.Na__Config__Settings
            node = settings[group.to_s]
            node.is_a?(Hash) ? node[key.to_s] : nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Save Settings From the Dialog (only known keys, coerced)
        # ------------------------------------------------------------
        # Returns the settings as now saved. A value equal to its default is
        # left out of the user file, so a later change of default reaches him.
        def self.Na__Config__SaveSettings(patch)
            defaults = self.Na__Config__GetOr({}, 'settings')
            current  = self.Na__UserConfig__All['settings']
            current  = current.is_a?(Hash) ? self.na_deep_copy(current) : {}

            (patch.is_a?(Hash) ? patch : {}).each do |group, values|
                next unless defaults[group.to_s].is_a?(Hash) && values.is_a?(Hash)

                values.each do |key, value|
                    default = defaults[group.to_s][key.to_s]
                    next if default.nil?

                    coerced = self.na_coerce(value, default)
                    next if coerced.nil?

                    current[group.to_s] ||= {}
                    if coerced == default
                        current[group.to_s].delete(key.to_s)
                    else
                        current[group.to_s][key.to_s] = coerced
                    end
                end
                current.delete(group.to_s) if current[group.to_s].is_a?(Hash) && current[group.to_s].empty?
            end

            self.na_write_user('settings', current)
            self.Na__Config__Settings
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | User Config (this PC only)
# -----------------------------------------------------------------------------

        # FUNCTION | The Whole User File
        # ------------------------------------------------------------
        def self.Na__UserConfig__All
            @na_user ||= (self.na_read_json(self.Na__Config__UserConfigPath) || {})
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Dialog's Own Remembered State (tab, columns, sort ...)
        # ------------------------------------------------------------
        def self.Na__UserConfig__Ui
            ui = self.Na__UserConfig__All['ui']
            ui.is_a?(Hash) ? ui : {}
        end
        # ---------------------------------------------------------------

        # FUNCTION | Remember One Piece of Dialog State
        # ------------------------------------------------------------
        # Values arrive as parsed JSON (strings, numbers, booleans, arrays,
        # objects) and are stored as they are; the page owns their meaning.
        def self.Na__UserConfig__SetUi(key, value)
            key = key.to_s
            return false if key.empty? || key.length > 60

            ui = self.na_deep_copy(self.Na__UserConfig__Ui)
            ui[key] = value
            self.na_write_user('ui', ui)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Naming Standards (prefixes, flag types, the handoff footer)
# -----------------------------------------------------------------------------

        # FUNCTION | The Standards (cached; validated on read too)
        # ------------------------------------------------------------
        def self.Na__Standards__All
            return @na_standards if @na_standards

            raw = self.na_read_json(self.Na__Config__StandardsPath) || {}
            normalised, issues = self.Na__Standards__Validate(raw)
            issues.each { |issue| Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Naming standards: #{issue}") }
            @na_standards = normalised
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Prefix Entries
        # ------------------------------------------------------------
        def self.Na__Standards__Prefixes
            self.Na__Standards__All['prefixes']
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Flag Types
        # ------------------------------------------------------------
        def self.Na__Standards__Flags
            self.Na__Standards__All['flags']
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Flag Type by Id (nil when unknown)
        # ------------------------------------------------------------
        def self.Na__Standards__Flag(flag_id)
            self.Na__Standards__Flags.find { |flag| flag['id'] == flag_id.to_s }
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Prefix by Id or Label (case-insensitive label)
        # ------------------------------------------------------------
        def self.Na__Standards__Prefix(reference)
            text = reference.to_s
            self.Na__Standards__Prefixes.find { |entry| entry['id'] == text } ||
                self.Na__Standards__Prefixes.find { |entry| entry['label'].casecmp(text).zero? }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Save the Standards From the Configure Tab
        # ------------------------------------------------------------
        # Returns [saved standards, issues]. Nothing is written while any issue
        # remains: the tab shows them and keeps Adam's edits.
        def self.Na__Standards__Save(data)
            normalised, issues = self.Na__Standards__Validate(data)
            return [self.Na__Standards__All, issues] unless issues.empty?

            normalised['schema']  = 1
            normalised['about']   = self.Na__Standards__All['about'] || ''
            normalised['updated'] = Time.now.strftime('%d-%b-%Y')
            path = self.Na__Config__StandardsPath
            FileUtils.cp(path, "#{path}.bak") if File.exist?(path)
            self.na_write_json(path, normalised)
            @na_standards = nil
            Na__AgentOutliner::Na__Notes.Na__Notes__Touch if defined?(Na__AgentOutliner::Na__Notes)   # <-- 0.1.9: which flag types wait may have changed
            [self.Na__Standards__All, []]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check and Tidy a Standards Hash
        # ------------------------------------------------------------
        def self.Na__Standards__Validate(data)
            data   = {} unless data.is_a?(Hash)
            issues = []
            prefixes = self.na_validate_prefixes(data['prefixes'], issues)
            flags    = self.na_validate_flags(data['flags'], issues)
            handoff  = data['handoff'].is_a?(Hash) ? data['handoff'] : {}
            footer   = handoff['footer'].to_s.strip[0, 2000]

            standards = {
                'schema'   => 1,
                'about'    => data['about'].to_s,
                'updated'  => data['updated'].to_s,
                'prefixes' => prefixes,
                'flags'    => flags,
                'handoff'  => { 'footer' => footer }
            }
            [standards, issues]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cache
# -----------------------------------------------------------------------------

        def self.Na__Config__ClearCache
            @na_app_config = nil
            @na_user       = nil
            @na_standards  = nil
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers - Validation
# -----------------------------------------------------------------------------

        def self.na_validate_prefixes(list, issues)
            seen_labels = {}
            seen_ids    = {}
            Array(list).each_with_index.map do |entry, index|
                next nil unless entry.is_a?(Hash)

                label = entry['label'].to_s.strip
                where = label.empty? ? "Prefix #{index + 1}" : label
                if label.empty?
                    issues << "#{where} has no label."
                    next nil
                end
                unless label.match?(NA_LABEL_PATTERN)
                    issues << "#{where}: use letters, numbers and dashes, with double underscores between parts (CAD__SideElevation__Left)."
                    next nil
                end
                if seen_labels[label.downcase]
                    issues << "#{where} is listed twice."
                    next nil
                end
                seen_labels[label.downcase] = true

                id = entry['id'].to_s.strip
                id = label.gsub(/[^A-Za-z0-9]+/, '_').gsub(/\A_+|_+\z/, '').downcase if id.empty?
                id = "#{id}_#{index}" if seen_ids[id]
                seen_ids[id] = true

                mode = %w[replace prefix face].include?(entry['mode'].to_s) ? entry['mode'].to_s : 'replace'   # face: 11-Nov-2026 (elevation faces)
                colour = entry['colour'].to_s.match?(NA_COLOUR_PATTERN) ? entry['colour'].to_s.downcase : '#64748b'
                category = entry['category'].to_s.strip
                category = 'General' if category.empty?

                {
                    'id'       => id,
                    'label'    => label,
                    'category' => category[0, 60],
                    'mode'     => mode,
                    'colour'   => colour,
                    'meaning'  => entry['meaning'].to_s.strip[0, 600]
                }
            end.compact
        end

        def self.na_validate_flags(list, issues)
            seen = {}
            flags = Array(list).each_with_index.map do |entry, index|
                next nil unless entry.is_a?(Hash)

                id    = entry['id'].to_s.strip
                label = entry['label'].to_s.strip
                where = label.empty? ? "Flag #{index + 1}" : label
                unless id.match?(NA_FLAG_ID_PATTERN)
                    issues << "#{where}: its id must be lower case letters, numbers and underscores (for_agent)."
                    next nil
                end
                if seen[id]
                    issues << "#{where}: the id #{id} is used twice."
                    next nil
                end
                if label.empty?
                    issues << "Flag #{id} has no label."
                    next nil
                end
                seen[id] = true

                {
                    'id'      => id,
                    'label'   => label[0, 40],
                    'colour'  => entry['colour'].to_s.match?(NA_COLOUR_PATTERN) ? entry['colour'].to_s.downcase : '#64748b',
                    'inbox'   => entry['inbox'] == true,
                    'meaning' => entry['meaning'].to_s.strip[0, 600]
                }
            end.compact
            issues << 'At least one flag type is needed.' if flags.empty?
            flags
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers - Files and Types
# -----------------------------------------------------------------------------

        def self.na_write_user(section, value)
            data = self.na_deep_copy(self.Na__UserConfig__All)
            data['schema'] = 1
            data[section] = value
            self.na_write_json(self.Na__Config__UserConfigPath, data)
            @na_user = data
            true
        rescue StandardError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('Saving the user settings failed.', error)
            false
        end

        def self.na_read_json(path)
            return nil unless File.exist?(path)

            text = File.read(path, mode: 'rb').force_encoding('UTF-8').delete_prefix("﻿")
            parsed = JSON.parse(text)
            parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError, EncodingError => error
            corrupt = "#{path.sub(/\.json\z/i, '')}.corrupt-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json"
            self.na_rename_quietly(path, corrupt)                                       # <-- Keep the bad file for Adam to look at
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Error("#{File.basename(path)} could not be read and was renamed #{File.basename(corrupt)}.", error)
            nil
        end

        def self.na_rename_quietly(from, to)
            File.rename(from, to)
            true
        rescue SystemCallError => error
            Na__AgentOutliner::Na__DebugTools.Na__Debug__Warn("Could not rename #{File.basename(from)}: #{error.message}")
            false
        end

        # Writes through a temporary file, then replaces the target, so a crash
        # mid write never leaves half a JSON file behind.
        def self.na_write_json(path, data)
            FileUtils.mkdir_p(File.dirname(path))
            temp = "#{path}.tmp"
            File.open(temp, 'wb') { |file| file.write(self.Na__Json__Pretty(data) + "\n") }
            File.delete(path) if File.exist?(path)
            File.rename(temp, path)
            true
        end

        # FUNCTION | JSON in the House Layout: Keys Padded Into a Column
        # ------------------------------------------------------------
        # Files people read (the standards are committed and diffed) keep the
        # aligned look of Adam's hand-written JSON. Short lists of plain values
        # stay on one line.
        def self.Na__Json__Pretty(value, indent = 0)
            pad = ' ' * indent
            case value
            when Hash
                return '{}' if value.empty?

                width = value.keys.map { |key| JSON.generate(key.to_s).length }.max
                lines = value.map do |key, item|
                    "#{pad}    #{JSON.generate(key.to_s).ljust(width)} : #{self.Na__Json__Pretty(item, indent + 4)}"
                end
                "{\n#{lines.join(",\n")}\n#{pad}}"
            when Array
                return '[]' if value.empty?

                if value.all? { |item| !item.is_a?(Hash) && !item.is_a?(Array) } && JSON.generate(value).length <= 90
                    return "[#{value.map { |item| JSON.generate(item) }.join(', ')}]"
                end

                lines = value.map { |item| "#{pad}    #{self.Na__Json__Pretty(item, indent + 4)}" }
                "[\n#{lines.join(",\n")}\n#{pad}]"
            else
                JSON.generate(value)
            end
        end
        # ---------------------------------------------------------------

        def self.na_coerce(value, default)
            case default
            when true, false
                value == true || value.to_s == 'true'
            when Integer
                number = self.na_float(value)
                number ? number.round : nil
            when Float
                self.na_float(value)
            when Array
                list = Array(value).map { |item| self.na_float(item) }
                return nil if list.empty? || list.any?(&:nil?)

                default.first.is_a?(Integer) ? list.map(&:round) : list
            when String
                text = value.to_s.strip
                return nil if default.start_with?('#') && !text.match?(NA_COLOUR_PATTERN)

                text[0, 200]
            end
        end

        # A finite Float, or nil for anything that is not a number.
        def self.na_float(value)
            number = Float(value)
            number.finite? ? number : nil
        rescue ArgumentError, TypeError
            nil
        end

        def self.na_deep_merge(base, over)
            merged = self.na_deep_copy(base)
            over.each do |key, value|
                merged[key] = value.is_a?(Hash) && merged[key].is_a?(Hash) ? self.na_deep_merge(merged[key], value) : value
            end
            merged
        end

        def self.na_deep_copy(value)
            JSON.parse(JSON.generate(value))
        rescue StandardError
            value.is_a?(Hash) ? value.dup : value
        end

# endregion -------------------------------------------------------------------

    end # module Na__ConfigStore
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
