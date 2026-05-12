# =============================================================================
# NA PROFILE TOOLS - DEBUG TOOLS
# =============================================================================
#
# FILE       : Na__ProfileTools__AppUtils__DebugTools__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__DebugTools
# PURPOSE    : Minimal logging helpers for scaffold modules
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer
    module Na__DebugTools

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_LOG_PREFIX = '[Na__ProfilePathTracer]'.freeze

    # endregion ----------------------------------------------------------------

        def self.Na__Debug__Info(message)
            puts "#{NA_LOG_PREFIX}[INFO] #{message}"
        end

        def self.Na__Debug__Warn(message)
            puts "#{NA_LOG_PREFIX}[WARN] #{message}"
        end

        def self.Na__Debug__Error(message, error = nil)
            puts "#{NA_LOG_PREFIX}[ERROR] #{message}"
            return nil unless error

            puts "  #{error.class}: #{error.message}"
            nil
        end

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
