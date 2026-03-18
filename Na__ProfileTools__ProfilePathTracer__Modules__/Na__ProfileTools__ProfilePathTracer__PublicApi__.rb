# =============================================================================
# NA PROFILE TOOLS - PROFILE PATH TRACER - PUBLIC API
# =============================================================================
#
# FILE       : Na__ProfileTools__ProfilePathTracer__PublicApi__.rb
# PURPOSE    : Public entry points used by loader and other plugins
# CREATED    : 2026
#
# =============================================================================

module Na__ProfileTools__ProfilePathTracer

    # -------------------------------------------------------------------------
    # REGION | Public API - Dialog
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__OpenDialog
        Na__DialogManager.Na__Dialog__Show
    rescue => error
        Na__DebugTools.Na__Debug__Error('Unable to open dialog.', error)
        UI.messagebox("Na Profile Path Tracer failed to open.\n\n#{error.message}")
    end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public API - Headless Execution
    # -------------------------------------------------------------------------

    def self.Na__PublicApi__RunHeadless(config_hash = {})
        Na__HeadlessRunner.Na__Headless__Run(config_hash)
    end

    # endregion ----------------------------------------------------------------

end

# =============================================================================
# END OF FILE
# =============================================================================
