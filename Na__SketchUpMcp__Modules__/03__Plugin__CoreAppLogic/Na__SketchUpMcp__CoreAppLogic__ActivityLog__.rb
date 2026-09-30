# =============================================================================
# NA SKETCHUP MCP - CORE ACTIVITY LOG
# =============================================================================
#
# FILE       : Na__SketchUpMcp__CoreAppLogic__ActivityLog__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__ActivityLog
# PURPOSE    : Keep an in-memory audit trail of every request an agent makes
# CREATED    : 2026
#
# WHY THIS EXISTS:
# An agent driving the model should never be invisible. Every request lands
# here (tool, time taken, success, one-line outcome), the status dialog shows
# the newest first, and SketchUp's status bar echoes the latest one.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__ActivityLog

# -----------------------------------------------------------------------------
# REGION | Recording
# -----------------------------------------------------------------------------

        def self.Na__ActivityLog__Record(tool_name, elapsed_ms, success_flag, message_text)
            entry = {
                'time'    => Time.now.strftime('%H:%M:%S'),
                'tool'    => tool_name.to_s,
                'ms'      => elapsed_ms.round,
                'ok'      => success_flag ? true : false,
                'message' => message_text.to_s[0, 240]
            }

            na_entries.unshift(entry)
            na_entries.pop while na_entries.length > na_max_entries
            na_counters[success_flag ? 'ok' : 'failed'] += 1

            na_echo_to_status_bar(entry)
            na_echo_to_console(entry)
            na_notify_dialog(entry)
            entry
        rescue StandardError => error
            puts "[Na__SketchUpMcp] Activity log warning: #{error.class}: #{error.message}"
            nil
        end

        def self.Na__ActivityLog__Entries
            na_entries.dup
        end

        def self.Na__ActivityLog__Counters
            na_counters.dup
        end

        def self.Na__ActivityLog__Clear
            @na_entries = []
            @na_counters = nil
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_entries
            @na_entries ||= []
        end

        def self.na_counters
            @na_counters ||= { 'ok' => 0, 'failed' => 0 }
        end

        def self.na_max_entries
            Na__ConfigLoader.Na__ConfigLoader__Get('activity_log', 'max_entries', 200).to_i
        end

        def self.na_echo_to_status_bar(entry)
            return unless Na__ConfigLoader.Na__ConfigLoader__Get('safety', 'status_bar_messages', true)

            outcome = entry['ok'] ? 'ok' : 'FAILED'
            Sketchup.status_text = "MCP: #{entry['tool']} #{outcome} (#{entry['ms']} ms)"
        rescue StandardError
            nil
        end

        def self.na_echo_to_console(entry)
            return unless Na__ConfigLoader.Na__ConfigLoader__Get('activity_log', 'console_logging', false)

            puts "[Na__SketchUpMcp] #{entry['time']} #{entry['tool']} #{entry['ok'] ? 'ok' : 'FAILED'} #{entry['ms']}ms #{entry['message']}"
        end

        def self.na_notify_dialog(entry)
            return unless defined?(Na__DialogManager) &&
                          Na__DialogManager.respond_to?(:Na__DialogManager__PushActivity)

            Na__DialogManager.Na__DialogManager__PushActivity(entry)
        end

# endregion -------------------------------------------------------------------

    end # module Na__ActivityLog
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
