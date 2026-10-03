# =============================================================================
# NA POINT CLOUD VIEWER - APP UTILS - DEBUG TOOLS
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppUtils__DebugTools__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__DebugTools
# PURPOSE    : Console logging plus a short in-memory technical log. Users see
#              plain-English messages in the dialog; the class names, messages
#              and backtraces behind them go here (Settings > Technical Log).
#
# =============================================================================

module Na__PointCloudViewer
    module Na__DebugTools

    # -------------------------------------------------------------------------
    # REGION | State
    # -------------------------------------------------------------------------

        NA_LOG_PREFIX     = '[Na__PointCloudViewer]'.freeze
        NA_LOG_RING_LIMIT = 80

        @na_log_ring = [] unless defined?(@na_log_ring)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Debug__Info(message)
            self.na_record('info', message.to_s)
        end

        def self.Na__Debug__Warn(message)
            self.na_record('warn', message.to_s)
        end

        def self.Na__Debug__Error(message, error = nil)
            detail = message.to_s
            if error
                detail = "#{detail} | #{error.class}: #{error.message}"
                trace  = Array(error.backtrace).first(6).join("\n    ")
                detail = "#{detail}\n    #{trace}" unless trace.empty?
            end
            self.na_record('error', detail)
        end

        # Newest last. Each entry: { 'time', 'level', 'message' }.
        def self.Na__Debug__RecentEntries(limit = 30)
            @na_log_ring.last(limit)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_record(level, message)
            label = level == 'info' ? '' : " #{level.upcase}"
            puts "#{NA_LOG_PREFIX}#{label} #{message}"
            @na_log_ring << { 'time' => Time.now.strftime('%H:%M:%S'), 'level' => level, 'message' => message }
            @na_log_ring.shift while @na_log_ring.length > NA_LOG_RING_LIMIT
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
