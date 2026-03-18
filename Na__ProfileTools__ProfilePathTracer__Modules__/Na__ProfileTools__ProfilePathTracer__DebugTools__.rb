# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - DEBUG TOOLS
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__DebugTools__.rb
# PURPOSE    : Minimal logging helpers for scaffold modules
# CREATED    : 2026
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
