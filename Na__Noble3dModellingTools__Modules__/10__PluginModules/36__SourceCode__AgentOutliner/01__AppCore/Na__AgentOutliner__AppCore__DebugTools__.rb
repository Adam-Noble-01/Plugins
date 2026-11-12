# =============================================================================
# NA AGENT OUTLINER - APP CORE - DEBUG TOOLS
# =============================================================================
#
# FILE       : Na__AgentOutliner__AppCore__DebugTools__.rb
# NAMESPACE  : Na__AgentOutliner::Na__DebugTools
# MODULE     : Na__DebugTools (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : The one place this tool writes diagnostics: a short in-memory
#              log the Settings tab shows as its Technical Log, echoed to the
#              Ruby Console only in Dev Mode (errors always)
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - WHY A RING BUFFER: observers and timers swallow exceptions, so a fault in
#   the change tracker would otherwise be invisible. Every rescue in this tool
#   lands here, and Adam (or an agent through agent_outliner summary) can read
#   the last lines without a Ruby Console open.
# - Console output is kept off the hot path: a visible Ruby Console stutters
#   the viewport, so only errors print unless Dev Mode is on.
#
# =============================================================================

module Na__AgentOutliner
    module Na__DebugTools

# -----------------------------------------------------------------------------
# REGION | Constants and State
# -----------------------------------------------------------------------------

        NA_LOG_LIMIT = 300 unless defined?(NA_LOG_LIMIT)                                # <-- Lines kept for the Technical Log

        @na_lines = [] unless defined?(@na_lines)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Logging API
# -----------------------------------------------------------------------------

        # FUNCTION | Log a Line (Console Only in Dev Mode)
        # ------------------------------------------------------------
        def self.Na__Debug__Log(text)
            self.na_append('info', text)
            puts "[Na__AgentOutliner] #{text}" if self.Na__Debug__DevMode?
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Log a Warning (Console Only in Dev Mode)
        # ------------------------------------------------------------
        def self.Na__Debug__Warn(text)
            self.na_append('warn', text)
            puts "[Na__AgentOutliner] WARNING: #{text}" if self.Na__Debug__DevMode?
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Log an Error (Always Printed, With the First Backtrace Lines)
        # ------------------------------------------------------------
        def self.Na__Debug__Error(text, error = nil)
            detail = error ? "#{text} #{error.class}: #{error.message}" : text.to_s
            self.na_append('error', detail)
            puts "[Na__AgentOutliner] ERROR: #{detail}"
            if error && error.backtrace && self.Na__Debug__DevMode?
                puts error.backtrace.first(8).join("\n")
            end
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Lines the Technical Log Shows (Newest Last)
        # ------------------------------------------------------------
        def self.Na__Debug__Lines
            @na_lines.dup
        end
        # ---------------------------------------------------------------

        # FUNCTION | Is Dev Mode On? (Settings tab)
        # ------------------------------------------------------------
        def self.Na__Debug__DevMode?
            return false unless defined?(Na__AgentOutliner::Na__ConfigStore)

            Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('debug', 'dev_mode') ? true : false
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Helpers
# -----------------------------------------------------------------------------

        def self.na_append(level, text)
            @na_lines << { 'time' => Time.now.strftime('%H:%M:%S'), 'level' => level, 'text' => text.to_s[0, 600] }
            @na_lines.shift while @na_lines.length > NA_LOG_LIMIT
        end

# endregion -------------------------------------------------------------------

    end # module Na__DebugTools
end # module Na__AgentOutliner

# =============================================================================
# END OF FILE
# =============================================================================
