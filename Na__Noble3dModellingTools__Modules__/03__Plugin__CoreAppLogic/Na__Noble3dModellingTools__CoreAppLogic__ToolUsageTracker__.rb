# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CORE TOOL USAGE TRACKER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLogic__ToolUsageTracker__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__ToolUsageTracker
# PURPOSE    : Count every tool launch and rank the quick-launch row
# CREATED    : 30-Sep-2026
#
# DESIGN NOTES:
# - Every launch path (dialog card, quick-launch card, menu, hotkey) goes
#   through Na__Noble3dModellingTools__RunCommandById, which calls
#   RecordCommandUse here. Every command is counted, including ones kept off
#   the quick-launch row, so the log is a complete record to review later.
# - The log lives in 91__UserConfig__LocalOnly, which is git-ignored: usage is
#   per user and per PC and never travels with the plugin.
# - The file is rewritten on each launch with tools sorted most-used first, so
#   opening it shows the ranking at a glance. It is re-read every time, so a
#   hand edit (e.g. deleting an entry to reset it) takes effect immediately.
# - A file that cannot be parsed is renamed aside (.corrupt-<time>.json), never
#   silently overwritten, and a fresh log is started.
# - Tracking must never block a tool: every public method rescues and logs.
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__Noble3dModellingTools
    module Na__ToolUsageTracker

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_USAGE_SCHEMA        = 1
        NA_QUICK_LAUNCH_LIMIT  = 6
        NA_SOURCES             = %w[dialog quick_launch menu_hotkey].freeze
        NA_DEFAULT_SOURCE      = 'menu_hotkey'.freeze
        NA_LOG_ABOUT           = 'Na Noble3d Modelling Tools launch counts for this user on this PC. ' \
                                 'Tools are sorted most-used first; the top six quick-launch-eligible ' \
                                 'tools fill the row under the search bar. Delete this file to reset.'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # Count one launch of a registry command. Unknown command IDs are ignored.
        def self.Na__Noble3dModellingTools__RecordCommandUse(command_id, source = NA_DEFAULT_SOURCE)
            command_entry = Na__ConfigLoader.Na__Noble3dModellingTools__CommandById(command_id)
            return false unless command_entry

            usage_log = na_read_log(true)
            timestamp = na_timestamp
            source_key = NA_SOURCES.include?(source.to_s) ? source.to_s : NA_DEFAULT_SOURCE

            entry = usage_log['tools'][command_entry['command_id']] ||= {
                'count'      => 0,
                'by_source'  => {},
                'first_used' => timestamp
            }
            entry['short_name'] = command_entry['short_name']
            entry['menu_text']  = command_entry['menu_text']
            entry['count']      = entry['count'].to_i + 1
            entry['by_source']  = {} unless entry['by_source'].is_a?(Hash)
            entry['by_source'][source_key] = entry['by_source'][source_key].to_i + 1
            entry['last_used']  = timestamp

            usage_log['total_launches'] = usage_log['total_launches'].to_i + 1
            usage_log['updated_at']     = timestamp
            na_write_log(usage_log)
            true
        rescue => error
            puts "[Na__Noble3dModellingTools] Tool usage record warning: #{error.class}: #{error.message}"
            false
        end

        # The most-used quick-launch-eligible commands, most used first.
        # Each item: { 'command_id', 'short_name', 'menu_text', 'count' }.
        def self.Na__Noble3dModellingTools__QuickLaunchCommands(limit = NA_QUICK_LAUNCH_LIMIT)
            usage_log = na_read_log(false)

            candidates = usage_log['tools'].filter_map do |command_id, entry|
                next unless entry.is_a?(Hash) && entry['count'].to_i > 0

                command_entry = Na__ConfigLoader.Na__Noble3dModellingTools__CommandById(command_id)
                next unless command_entry && command_entry['quick_launch']

                {
                    'command_id' => command_id,
                    'short_name' => command_entry['short_name'],
                    'menu_text'  => command_entry['menu_text'],
                    'count'      => entry['count'].to_i,
                    'last_used'  => entry['last_used'].to_s
                }
            end

            na_sort_most_used_first(candidates).first(limit)
        rescue => error
            puts "[Na__Noble3dModellingTools] Quick launch ranking warning: #{error.class}: #{error.message}"
            []
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Log File Read / Write
# -----------------------------------------------------------------------------

        def self.na_read_log(quarantine_corrupt)
            file_path = Na__PathResolver.Na__Noble3dModellingTools__ToolUsageLogFilePath
            return na_new_log unless File.exist?(file_path)

            parsed = JSON.parse(File.read(file_path, encoding: 'UTF-8'))
            raise JSON::ParserError, 'root is not an object' unless parsed.is_a?(Hash)

            parsed['tools'] = {} unless parsed['tools'].is_a?(Hash)
            parsed
        rescue JSON::ParserError => error
            puts "[Na__Noble3dModellingTools] Tool usage log unreadable (#{error.message})."
            na_quarantine_corrupt_log(file_path) if quarantine_corrupt
            na_new_log
        end

        def self.na_write_log(usage_log)
            file_path = Na__PathResolver.Na__Noble3dModellingTools__ToolUsageLogFilePath
            FileUtils.mkdir_p(File.dirname(file_path))

            ordered_log = {
                'schema'         => NA_USAGE_SCHEMA,
                'about'          => NA_LOG_ABOUT,
                'created_at'     => usage_log['created_at'] || na_timestamp,
                'updated_at'     => usage_log['updated_at'] || na_timestamp,
                'total_launches' => usage_log['total_launches'].to_i,
                'tools'          => na_sorted_tools_hash(usage_log['tools'])
            }

            temp_path = "#{file_path}.tmp"
            File.write(temp_path, JSON.pretty_generate(ordered_log) + "\n", encoding: 'UTF-8')
            File.rename(temp_path, file_path)
        end

        def self.na_quarantine_corrupt_log(file_path)
            aside_path = file_path.sub(/\.json\z/, ".corrupt-#{Time.now.strftime('%Y%m%d-%H%M%S')}.json")
            File.rename(file_path, aside_path)
            puts "[Na__Noble3dModellingTools] Moved unreadable tool usage log aside: #{aside_path}"
        rescue => error
            puts "[Na__Noble3dModellingTools] Could not move unreadable tool usage log: #{error.class}: #{error.message}"
        end

        def self.na_new_log
            timestamp = na_timestamp
            {
                'schema'         => NA_USAGE_SCHEMA,
                'created_at'     => timestamp,
                'updated_at'     => timestamp,
                'total_launches' => 0,
                'tools'          => {}
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Ordering Helpers
# -----------------------------------------------------------------------------

        # Most launches first; ties go to the most recently used, then by name.
        def self.na_sort_most_used_first(items)
            items.sort do |a, b|
                (b['count'].to_i <=> a['count'].to_i).nonzero? ||
                    (b['last_used'].to_s <=> a['last_used'].to_s).nonzero? ||
                    (a['short_name'].to_s <=> b['short_name'].to_s)
            end
        end

        def self.na_sorted_tools_hash(tools_hash)
            items = tools_hash.select { |_id, entry| entry.is_a?(Hash) }.map do |command_id, entry|
                entry.merge('__command_id' => command_id)
            end

            na_sort_most_used_first(items).each_with_object({}) do |item, sorted|
                command_id = item.delete('__command_id')
                sorted[command_id] = {
                    'short_name' => item['short_name'],
                    'menu_text'  => item['menu_text'],
                    'count'      => item['count'].to_i,
                    'by_source'  => item['by_source'] || {},
                    'first_used' => item['first_used'],
                    'last_used'  => item['last_used']
                }
            end
        end

        def self.na_timestamp
            Time.now.strftime('%Y-%m-%dT%H:%M:%S')
        end

# endregion -------------------------------------------------------------------

    end # module Na__ToolUsageTracker
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
