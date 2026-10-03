# =============================================================================
# NA POINT CLOUD VIEWER - APP UTILS - PERFORMANCE STATS
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppUtils__PerfStats__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__PerfStats
# PURPOSE    : Monotonic timing and number formatting for user messages.
#
# =============================================================================

module Na__PointCloudViewer
    module Na__PerfStats

    # -------------------------------------------------------------------------
    # REGION | Clock
    # -------------------------------------------------------------------------

        def self.Na__Perf__NowMs
            Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
        end

        # Times the block; returns [block_result, elapsed_ms].
        def self.Na__Perf__Measure
            started = self.Na__Perf__NowMs
            result  = yield
            [result, self.Na__Perf__NowMs - started]
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Formatting
    # -------------------------------------------------------------------------

        # 2000000 -> "2,000,000" for user-facing messages.
        def self.Na__Perf__Thousands(value)
            value.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
